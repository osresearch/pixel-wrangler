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


// Deserialize 10 input bits into a 10-bit register,
// clocking on the rising edge of the bit clock using a DDR pin
// to capture two bits per clock (the PLL clock runs at 5x the TMDS clock)
// the bits are sent LSB first
module tmds_shift_register_ddr(
	input bit_clk,
	input in_p,
	output [BITS-1:0] out
);
	parameter BITS = 10;
	reg [BITS-1:0] out;
	wire in0, in1;

	SB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) diff_io (
		.PACKAGE_PIN(in_p),
		.INPUT_CLK(bit_clk),
		.D_IN_0(in0), // pos edge of bit_clk
		.D_IN_1(in1)  // neg edge of bit_clk
	);

	always @(posedge bit_clk)
		out <= { in0, in1, out[BITS-1:2] };
endmodule

// non ddr version for a 10 bit shift register
module tmds_shift_register(
	input bit_clk,
	input in_p,
	output [BITS-1:0] out
);
	parameter BITS = 10;
	reg [BITS-1:0] out;
	wire in0;

	SB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) diff_io (
		.PACKAGE_PIN(in_p),
		.INPUT_CLK(bit_clk),
		.D_IN_0(in0) // pos edge of bit_clk
	);

	always @(posedge bit_clk)
		out <= { in0, out[BITS-1:1] };
endmodule

// detect a control messgae in the shift register and use it to resync our pixel clock
// tracks if our clock is still in sync with the old values
module tmds_sync_recognizer(
	input clk,
	input [9:0] in,
	output valid,
	output [3:0] phase
);
	//parameter CTRL_00 = 10'b1101010100; // 354
	//parameter CTRL_01 = 10'b0010101011; // 0AB
	//parameter CTRL_10 = 10'b0101010100; // 154
	parameter CTRL_11 = 10'b1010101011; // 2AB
	parameter DELAY_BITS = 18;

	reg valid;
	reg [3:0] phase = 0;
	reg [DELAY_BITS:0] counter;

	always @(posedge clk)
	begin
		counter <= counter + 1;

		if (in == CTRL_11)
		begin
			// we have a good control word!
			valid <= 1;
			counter <= 0;
		end else
		if (counter[DELAY_BITS])
		begin
			// no recent control word! adjust the phase
			if (phase == 4'h9)
				phase <= 0;
			else
				phase <= phase + 1;

			valid <= 0;
			counter <= 0;
		end
	end
endmodule


module tmds_clock_cross(
	input clk,
	input bit_clk,
	input [3:0] phase,
	input [9:0] d0_data,
	input [9:0] d1_data,
	input [9:0] d2_data,
	output [9:0] d0,
	output [9:0] d1,
	output [9:0] d2
);
	reg wen;
	reg [3:0] bit_counter = 0;

	always @(posedge bit_clk)
	begin
		wen <= bit_counter == phase;

		if (bit_counter == 4'h9)
			bit_counter <= 0;
		else
			bit_counter <= bit_counter + 1;
	end

	// transfer the shift registers to the clk domain
	// through two dual port block rams in 16-bit wide mode
	ram #(
		.ADDR_WIDTH(1),
		.DATA_WIDTH(30),
	) clock_cross(
		.wr_clk(bit_clk),
		.wr_enable(wen),
		.wr_addr(0),
		.wr_data({d0_data, d1_data, d2_data}),
		.rd_clk(clk),
		.rd_addr(0),
		.rd_data({d0,d1,d2})
	);
endmodule


// Synchronize the three channels with the TMDS clock and unknown phase
// of the bits.  Returns the raw 8b10b encoded values for futher processing
// and a TMDS synchronize clock for the data stream.  The data are only valid
// when locked
module hdmi_raw(
	input d0_p,
	input d1_p,
	input d2_p,
	input clk_p,
	input [3:0] pll_delay,

	// d0,d1,d2 are in clk domain
	output [9:0] d0,
	output [9:0] d1,
	output [9:0] d2,
	output valid, // good pixel data
	output locked, // only timing data
	output clk,
	output bit_clk
);
	wire clk; // 25 MHz decoded from TDMS input
	wire bit_clk; // 250 MHz PLL'ed from TMDS clock (or 125 MHz if DDR)
	reg pixel_strobe, pixel_valid; // when new pixels are detected by the synchronizer
	wire hdmi_locked;
	assign locked = hdmi_locked;
	reg valid;

	SB_GB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) differential_clock_input (
		.PACKAGE_PIN(clk_p),
		.GLOBAL_BUFFER_OUTPUT(clk)
	);

	hdmi_pll pll(
		.clock_in(clk),
		.clock_out(bit_clk),
		.locked(hdmi_locked),
		.delay(pll_delay)
	);

	// bit_clk domain
	wire [9:0] d0_data;
	wire [9:0] d1_data;
	wire [9:0] d2_data;

	tmds_shift_register d0_shift(
		.bit_clk(bit_clk),
		.in_p(d0_p),
		.out(d0_data)
	);

	tmds_shift_register d1_shift(
		.bit_clk(bit_clk),
		.in_p(d1_p),
		.out(d1_data)
	);

	tmds_shift_register d2_shift(
		.bit_clk(bit_clk),
		.in_p(d2_p),
		.out(d2_data)
	);

	// detect the pixel clock from the PLL'ed bit_clk
	// only channel 0 carries the special command words
	wire [3:0] phase;

	tmds_sync_recognizer d0_sync_recognizer(
		.clk(clk),
		.in(d0),
		.phase(phase),
		.valid(pixel_valid)
	);

	// cross the data words from bit_clk to clk domain
	tmds_clock_cross crosser(
		.clk(clk),
		.bit_clk(bit_clk),
		.phase(phase),
		.d0_data(d0_data),
		.d1_data(d1_data),
		.d2_data(d2_data),
		.d0(d0),
		.d1(d1),
		.d2(d2)
	);

	always @(posedge clk)
	begin
		valid <= hdmi_locked && pixel_valid;
	end
endmodule

module hdmi_decode(
	input clk,
	input [9:0] hdmi_d0,
	input [9:0] hdmi_d1,
	input [9:0] hdmi_d2,

	// data valid should be based on sync pulses, so ignore it for now
	output data_valid,
	output [7:0] d0,
	output [7:0] d1,
	output [7:0] d2,

	// these hold value so sync_valid is not necessary
	output sync_valid,
	output hsync,
	output vsync,

	// terc4 data is not used yet
	output ctrl_valid,
	output [3:0] ctrl
);
	tmds_decode d0_decoder(
		.clk(clk),
		.in(hdmi_d0),
		.data(d0),
		.sync({vsync,hsync}),
		.ctrl(ctrl),
		.data_valid(data_valid),
		.sync_valid(sync_valid),
		.ctrl_valid(ctrl_valid),
	);

	// audio data is on d1 and d2, but we don't handle it yet
	tmds_decode d1_decoder(
		.clk(clk),
		.in(hdmi_d1),
		.data(d1),
	);

	tmds_decode d2_decoder(
		.clk(clk),
		.in(hdmi_d2),
		.data(d2),
	);

endmodule


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


	wire hdmi_clk, hdmi_locked, hdmi_bit_clk;
	wire hdmi_valid;
	wire [9:0] hdmi_d0;
	wire [9:0] hdmi_d1;
	wire [9:0] hdmi_d2;

	wire data_valid;
	wire [7:0] d0;
	wire [7:0] d1;
	wire [7:0] d2;
	wire hsync, vsync;

	// unused for now
	reg [3:0] pll_delay = 0;

	hdmi_raw hdmi_raw_i(
		// physical inputs
		.clk_p(gpio_37),
		.d0_p(gpio_42),
		.d1_p(gpio_43),
		.d2_p(gpio_26),

		// tuning for bit clock
		.pll_delay(pll_delay),

		// outputs
		.clk(hdmi_clk),
		.bit_clk(hdmi_bit_clk),
		.locked(hdmi_locked),
		.valid(hdmi_valid),
		.d0(hdmi_d0),
		.d1(hdmi_d1),
		.d2(hdmi_d2),
	);

	hdmi_decode hdmi_decode_i(
		.clk(hdmi_clk),
		.hdmi_d0(hdmi_d0),
		.hdmi_d1(hdmi_d1),
		.hdmi_d2(hdmi_d2),

		// outputs
		.hsync(hsync),
		.vsync(vsync),
		.d0(d0),
		.d1(d1),
		.d2(d2),
		.data_valid(data_valid)
	);

	reg guard_band;
	always @(posedge hdmi_clk)
		guard_band <= hdmi_d0 == 10'h2CC;

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
	wire pulse = hdmi_locked && hdmi_clk_counter[24];
	assign led_r = !(pulse && !hdmi_valid); // red means TDMS sync, no pixel data
	assign led_g = !(pulse &&  hdmi_valid); // green means good pixel data

	//assign gpio_28 = hdmi_clk;
	assign gpio_2 = in_window; // hsync; // hdmi_valid;
	//assign gpio_2 = hdmi_valid;
	assign gpio_28 = vsync;

	always @(posedge hdmi_clk)
	begin
		if (hdmi_locked)
			hdmi_clk_counter <= hdmi_clk_counter + 1;
		else
			hdmi_clk_counter <= 0;

		if (hdmi_clk_counter == 25'h1FFFFFF)
			pll_delay <= pll_delay + 1;

		//gpio_28 <= hsync;
	end

	always @(posedge hdmi_bit_clk)
	begin
		if (hdmi_locked)
			hdmi_bit_counter <= hdmi_bit_counter + 1;
		else
			hdmi_bit_counter <= 0;
	end
endmodule
