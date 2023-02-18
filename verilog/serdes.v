/*
 * HDMI deserializer; outputs raw 10 bit values on every pixel clock.
 *
 * Requires a 5x or 10x PLL from the pixel clock.
 * Clock input should use a global buffer input
 * -- app note says " Global Buffer Input 7 (GBIN7) is the only one that supports differential clock inputs."
 * -- but experimentally only 37 works.
 *
 * Pair Inputs must use negative pin of differential pairs.
 * The positive pin *must not be mentioned* as an input.
 *
 * The bit clock and pixel clock have a constant, but unknown phase.
 * We should have a "tracking" function that tries to ensure it lines up.
 *
 * https://www.analog.com/en/design-notes/video-display-signals-and-the-max9406-dphdmidvi-level-shifter8212part-i.html
 * V+H sync and audio header on Blue (D0)
 * Audio data on Red and Green
 * Data island period is encoded with TERC4; can we ignore it?
 *
 * sync pulses are active low
 * H sync keeps pulsing while V is low (twice)
 * V sync is 63 usec, every 60 Hz
 * H sync is 4 usec, every 32 usec
 *
 * 640x480 frame is actually sent as an 800x525 frame.
 * hbi goes 80 into X, vbi goes 22 into y
 */
`default_nettype none
`include "hdmi_pll.v"
`include "tmds.v"
`include "mem.v"
`include "uart.v"


module hdmi_framebuffer(
	input clk,
	input valid,
	input hsync,
	input vsync,
	input data_valid,
	input [7:0] d0,
	input [7:0] d1,
	input [7:0] d2,

	output [ADDR_WIDTH-1:0] waddr,
	output [7:0] wdata,
	output wen,
	output in_window
);
	parameter ADDR_WIDTH = 13;
	parameter [11:0] MIN_X = 50;
	parameter [11:0] MIN_Y = 50;
	parameter [11:0] WIDTH = 128;
	parameter [11:0] HEIGHT = 100;

	reg [11:0] xaddr;
	reg [11:0] yaddr;
	wire [11:0] xoffset = xaddr - MIN_X;
	wire [11:0] yoffset = yaddr - MIN_Y;
	wire in_window = (xoffset < WIDTH) && (yoffset < HEIGHT);

	reg [ADDR_WIDTH-1:0] waddr;
	reg [7:0] wdata;
	reg wen;
	reg last_hsync;

	always @(posedge clk)
	begin
		wen <= 0;
		last_hsync <= hsync;

		if (!valid)
		begin
			// literally nothing to do
		end else
		if (!vsync)
		begin
			// edge triggered, but we can hold this as long as we need to
			yaddr <= 0;
			xaddr <= 0;
		end else
		if (!hsync) begin
			// only advance the y on the falling edge of hsync
			if (last_hsync)
				yaddr <= yaddr + 1;
			xaddr <= 0;
		end else
		if (data_valid) begin
			xaddr <= xaddr + 1;

			if (in_window)
				wen <= 1;

			// we only have one channel right now
			// width should be a power of two
			waddr <= xoffset + (yoffset * WIDTH);
			wdata <= d0;
		end
	end
endmodule
	

module top(
	output serial_txd,
	input serial_rxd,
	output spi_cs,
	output led_r,
	output led_g,

	// debug output
	output gpio_28,
	output gpio_2,

	// hdmi clock 
	input gpio_37, // pair input gpio_4,

	// hdmi pairs 36/43, 38/42, 26/27
	input gpio_43, // pair input gpio_36,
	input gpio_42, // pair input gpio_38,
	input gpio_26, // pair input gpio_27
);
	assign spi_cs = 1; // it is necessary to turn off the SPI flash chip
	reg reset = 0;
	wire clk_48mhz;
	SB_HFOSC inthosc(.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk_48mhz));
	wire clk = clk_48mhz;


	wire hdmi_clk, hdmi_bit_clk;
	wire hdmi_valid;

	wire data_valid;
	wire [7:0] d0;
	wire [7:0] d1;
	wire [7:0] d2;
	wire hsync, vsync;

	// unused for now
	reg [3:0] pll_delay = 0;

	tmds_decoder tmds_decoder_i(
		// physical inputs
		.clk_p(gpio_37),
		.d0_p(gpio_42),
		.d1_p(gpio_43),
		.d2_p(gpio_26),

		// outputs
		.clk(hdmi_clk),
		.bit_clk(hdmi_bit_clk),
		.locked(hdmi_valid),
		.hsync(hsync),
		.vsync(vsync),
		.d0(d0),
		.d1(d1),
		.d2(d2),
		.data_valid(data_valid)
	);

	parameter ADDR_WIDTH = 16;
	parameter WIDTH = 256;
	parameter HEIGHT = 200;
	parameter MIN_X = 40;
	parameter MIN_Y = 40;

	wire [ADDR_WIDTH-1:0] waddr;
	wire [7:0] wdata;

	wire wen;
	reg [ADDR_WIDTH-1:0] raddr;
	wire [7:0] rdata;
	ram #(
		.ADDR_WIDTH(ADDR_WIDTH),
		.DATA_WIDTH(1),
		.NUM_WORDS(WIDTH*HEIGHT)
	) fb_ram(
		.rd_clk(clk),
		.rd_addr(raddr),
		.rd_data(rdata[0]),
		.wr_clk(hdmi_clk),
		.wr_addr(waddr),
		.wr_enable(wen),
		.wr_data(wdata != 0)
	);

	wire in_window;

	hdmi_framebuffer #(
		.ADDR_WIDTH(ADDR_WIDTH),
		.WIDTH(WIDTH),
		.HEIGHT(HEIGHT),
		.MIN_X(MIN_X),
		.MIN_Y(MIN_Y)
	) hdmi_fb(
		.clk(hdmi_clk),
		.valid(hdmi_valid),
		.hsync(hsync),
		.vsync(vsync),
		.data_valid(1), //data_valid),
		.d0(d0),
		.d1(d1),
		.d2(d2),

		// outputs to the ram
		.waddr(waddr),
		.wdata(wdata),
		.wen(wen),
		.in_window(in_window)
	);


	// generate a 3 MHz/12 MHz serial clock from the 48 MHz clock
	// this is the 3 Mb/s maximum supported by the FTDI chip
	reg [3:0] baud_clk;
	always @(posedge clk_48mhz)
		baud_clk <= baud_clk + 1;

	wire [7:0] uart_rxd;
	wire uart_rxd_strobe;

	reg [7:0] uart_txd;
	reg uart_txd_strobe;
	wire uart_txd_ready;

	uart_rx rxd(
		.mclk(clk),
		.reset(reset),
		.baud_x4(baud_clk[1]), // 48 MHz / 4 == 12 Mhz
		.serial(serial_rxd),
		.data(uart_rxd),
		.data_strobe(uart_rxd_strobe)
	);

	uart_tx txd(
		.mclk(clk),
		.reset(reset),
		.baud_x1(baud_clk[3]), // 48 MHz / 16 == 3 Mhz
		.serial(serial_txd),
		.ready(uart_txd_ready),
		.data(uart_txd),
		.data_strobe(uart_txd_strobe)
	);

	reg [7:0] extra_data;
	reg [4:0] bit_count = 0;
	always @(posedge clk)
	begin
		uart_txd_strobe <= 0;

		if (bit_count != 8)
		begin
			// read up to eight bits from the fb
			extra_data <= { rdata[0], extra_data[7:1] };
			bit_count <= bit_count + 1;

			if (raddr == WIDTH*HEIGHT - 1)
				raddr <= 0;
			else
				raddr <= raddr + 1;
		end else
		if (uart_txd_ready && hdmi_valid && !uart_txd_strobe)
		begin
			uart_txd <= extra_data;
			uart_txd_strobe <= 1;
			bit_count <= 0;
		end
	end

	

	reg [24:0] hdmi_bit_counter;
	reg [24:0] hdmi_clk_counter;
	wire pulse = hdmi_valid && hdmi_clk_counter[24];
	assign led_r = !(pulse && !hdmi_valid); // red means TDMS sync, no pixel data
	assign led_g = !(pulse &&  hdmi_valid); // green means good pixel data

	//assign gpio_28 = hdmi_clk;
	assign gpio_2 = in_window; // hsync; // hdmi_valid;
	//assign gpio_2 = hdmi_valid;
	assign gpio_28 = vsync;

	always @(posedge hdmi_clk)
	begin
		if (hdmi_valid)
			hdmi_clk_counter <= hdmi_clk_counter + 1;
		else
			hdmi_clk_counter <= 0;

		if (hdmi_clk_counter == 25'h1FFFFFF)
			pll_delay <= pll_delay + 1;

		//gpio_28 <= hsync;
	end

	always @(posedge hdmi_bit_clk)
	begin
		if (hdmi_valid)
			hdmi_bit_counter <= hdmi_bit_counter + 1;
		else
			hdmi_bit_counter <= 0;
	end
endmodule
