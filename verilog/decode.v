/*
 * Debugging the TMDS channels on the Pixel Wrangler
 *
 */
`default_nettype none
`include "tmds.v"
`include "hdmi.v"
`include "uart.v"
`include "i2c.v"
`include "util.v"
`include "mem.v"
`include "pwm.v"

module top(
	output spi_cs,
	output led_r,
	output led_g,
	output led_b,

	//inout hdmi_sda, // OOPS conflicts with tmds clk
	input hdmi_scl,

	input tmds_d0n, // need to invert
	input tmds_d1n, // need to invert
	input tmds_d2p,
	input tmds_clkp,

	output gpio_0_0,
	output gpio_0_1,
	output gpio_0_2,
	output gpio_0_3,
	output gpio_0_4,
	output gpio_0_5,
	output gpio_0_6,
	//output gpio_0_7,
	inout gpio_0_7, // temporarily bodged to hdmi_sda

	output gpio_1_0,
	output gpio_1_1,
	output gpio_1_2,
	output gpio_1_3,
	output gpio_1_4,
	output gpio_1_5,
	output gpio_1_6,
	output gpio_1_7,

	input sw1
);
	assign spi_cs = 1; // it is necessary to turn off the SPI flash chip

	reg reset = 0;
	wire clk_48mhz;
	SB_HFOSC inthosc(.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk_48mhz));

	reg [3:0] clk_div;
	wire clk = clk_div[1];
	always @(posedge clk_48mhz)
		clk_div <= clk_div + 1;

	wire hdmi_clk;
	wire hdmi_locked;

	/*
	 * builtin RGB LED
	 */
	reg [7:0] bright_r = 0;
	reg [7:0] bright_g = 0;
	reg [7:0] bright_b = 0;

	rgb_drv rgb_drv_i(
		.clk(clk_48mhz),
		.enable(1'b1),
		.out({led_r,led_g,led_b}),
		.bright_r(bright_r),
		.bright_g(bright_g),
		.bright_b(bright_b)
	);

	// serial port interface
	reg uart_txd_strobe;
	wire uart_txd_ready;
	reg [7:0] uart_txd;

	wire uart_rxd_strobe;
	wire [7:0] uart_rxd;

	uart uart_i(
		.clk_48mhz(clk_48mhz),
		.clk(clk),
		.reset(reset),
		.serial_txd(gpio_1_7),
		.serial_rxd(gpio_1_6),
		.uart_txd(uart_txd),
		.uart_txd_strobe(uart_txd_strobe),
		.uart_txd_ready(uart_txd_ready),
		.uart_rxd(uart_rxd),
		.uart_rxd_strobe(uart_rxd_strobe)
	);

	wire sw1_in;
	tristate #(.PULLUP(1)) sw1_buffer(
		.pin(sw1),
		.enable(0),
		.data_in(sw1_in),
		.data_out(1'b0)
	);

	wire hdmi_clk; // 25 MHz decoded from TDMS input
	wire hdmi_bit_clk; // 250 MHz PLL'ed from TMDS clock (or 125 MHz if DDR)
	wire hdmi_valid;

	reg hdmi_reset = 0;
	reg [20:0] invalid_counter = 0;
	always @(posedge clk)
	begin
		if (!hdmi_valid)
			invalid_counter <= invalid_counter + 1;
		else
			invalid_counter <= invalid_counter == 0 ? 0 : invalid_counter - 1;

		hdmi_reset <= invalid_counter[20] || !sw1_in;
	end

	// hdmi_clk domain
	wire [9:0] tmds_d0, tmds_d1, tmds_d2;
	wire [1:0] hdmi_sync;
	wire data_valid;

	// hdmi_bit_clk domain
	wire [5:0] tmds_raw;

	tmds_raw_decoder #(
		.INVERT(3'b011)
	) tmds_decoder_i(
		.reset(hdmi_reset),

		// physical inputs
		.clk_p(tmds_clkp),
		.d0_p(tmds_d0n),
		.d1_p(tmds_d1n),
		.d2_p(tmds_d2p),

		// outputs
		.hdmi_clk(hdmi_clk),
		.bit_clk(hdmi_bit_clk),
		.valid(hdmi_valid),
		.locked(hdmi_locked),
		.d0(tmds_d0),
		.d1(tmds_d1),
		.d2(tmds_d2),
		.out_raw(tmds_raw)
	);

`define TMDS_RAW
`ifdef TMDS_RAW
	// just output a stream of TMDS data as it comes in

	parameter FIFO_WIDTH = 8;
	parameter FIFO_DEPTH = 13;
	reg [FIFO_WIDTH-1:0] wr_data;
	wire [FIFO_WIDTH-1:0] rd_data;

	reg [FIFO_DEPTH-1:0] wr_addr, rd_addr;

	// we want to record a full fifo of data and then wait
	// to get toggled back
	reg wr_enable = 0;
	reg start = 0;
	reg last_start = 0;

	always @(posedge hdmi_bit_clk)
	begin
		wr_data <= { hdmi_clk, hdmi_valid, tmds_raw };
		wr_addr <= wr_addr + 1;

		// restart at 0 when they signal us
		if (last_start != start)
			wr_addr <= 0;
		last_start <= start;
	end
		
	ram #(
		.DATA_WIDTH(FIFO_WIDTH),
		.ADDR_WIDTH(FIFO_DEPTH)
	) fifo(
		.wr_clk(hdmi_bit_clk),
		.wr_addr(wr_addr),
		.wr_data(wr_data),
		.wr_enable(wr_enable),

		.rd_clk(clk),
		.rd_addr(rd_addr),
		.rd_data(rd_data)
	);

	reg [21:0] delay = 0;

	always @(posedge clk)
	begin
		bright_b <= hdmi_locked ? 8'h80 : 8'h00;
		bright_r <= hdmi_valid ? 8'h00 : 8'h80;
		bright_g <= uart_txd_strobe ? 8'hF0 : 8'h00;
		uart_txd_strobe <= 0;

		if (rd_addr == 0)
		begin
			// when we hit the end of the buffer, ask them to start again
			delay <= 1;
			wr_enable <= 1;
			rd_addr <= 1;
			start <= ~start;
		end else
		if (delay != 0) begin
			delay <= delay + 1;
		end else
		if (uart_txd_ready && !uart_txd_strobe)
		begin
			// stop them from writing if they are
			wr_enable <= 0;

			// output the next byte
			uart_txd <= rd_data;
			uart_txd_strobe <= 1;
			rd_addr <= rd_addr + 1;
		end
	end
`else

	wire [7:0] d0, d1, d2;

	tmds_8b10b_decoder d0_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d0),
		.data(d0),
		.sync(hdmi_sync)
/*
		.ctrl(ctrl),
		.data_valid(data_valid),
		.sync_valid(sync_valid),
		.ctrl_valid(ctrl_valid),
*/
	);
	tmds_8b10b_decoder d1_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d1),
		.data(d1)
	);
	tmds_8b10b_decoder d2_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d2),
		.data(d2)
	);


	wire [11:0] hdmi_xaddr, hdmi_yaddr;

	hdmi_stream hdmi_s(
		// inputs
		.hdmi_clk(hdmi_clk),
		.valid(hdmi_valid),
		.sync(hdmi_sync),
		.d0(d0),
		.d1(d1),
		.d2(d2),
		// outputs
		.xaddr(hdmi_xaddr),
		.yaddr(hdmi_yaddr),
/*
		.vsync(vsync),
		.hsync(hsync),
		.rgb_valid(rgb_valid),
		.r(r),
		.g(g),
		.b(b)
*/
	);

	// record all three TMDS channels along with the clocks
	parameter FIFO_WIDTH = 32;
	parameter FIFO_DEPTH = 11;
	reg [FIFO_WIDTH-1:0] wr_data;
	wire [FIFO_WIDTH-1:0] rd_data;

	reg [FIFO_DEPTH-1:0] wr_addr, rd_addr;

	// we want to record a full fifo of data and then wait
	// to get toggled back
	reg wr_enable = 0;
	reg start = 0;
	reg last_start = 0;

	wire in_active_window = 1
		&& 100 <= hdmi_xaddr && hdmi_xaddr < 200
		&& 200 <= hdmi_yaddr && hdmi_yaddr < 300;

	always @(posedge hdmi_clk)
	begin
		wr_enable <= 0;
		wr_data <= { hdmi_reset, hdmi_valid, tmds_d2, tmds_d1, tmds_d0 };

		if (wr_addr != 11'h7FF && in_active_window)
		begin
			wr_enable <= 1;
			wr_addr <= wr_addr + 1;
		end

		// restart at 0 when they signal us
		if (last_start != start)
			wr_addr <= 0;
		last_start <= start;
	end
		

	ram #(
		.DATA_WIDTH(FIFO_WIDTH),
		.ADDR_WIDTH(FIFO_DEPTH)
	) fifo(
		.wr_clk(hdmi_clk),
		.wr_addr(wr_addr),
		.wr_data(wr_data),
		.wr_enable(wr_enable),

		.rd_clk(clk),
		.rd_addr(rd_addr),
		.rd_data(rd_data)
	);

	reg [31:0] uart_ring;
	reg [4:0] uart_bytes = 0;

	always @(posedge clk)
	begin
		bright_b <= hdmi_locked ? 8'h80 : 8'h00;
		bright_r <= hdmi_valid ? 8'h00 : 8'h80;
		bright_g <= uart_txd_strobe ? 8'hF0 : 8'h00;
		uart_txd_strobe <= 0;

		if (uart_txd_ready && !uart_txd_strobe && hdmi_locked)
		begin
			if (uart_bytes == 0)
			begin
				// get some bytes
				uart_ring <= rd_data;
				uart_bytes <= 6; // output two extra nul at the end

				// when we hit the end of the buffer, ask them to start again
				if (rd_addr == 0)
					start <= ~start;
				
				rd_addr <= rd_addr + 1;
			end else begin
				// output some bytes
				{ uart_txd, uart_ring } <= { uart_ring, 8'b00 };
				uart_txd_strobe <= 1;
				uart_bytes <= uart_bytes - 1;
			end
		end
	end
`endif

	// EDID interface is not yet exposed to the user
	wire sda_out;
	wire sda_in;
	wire sda_enable;

	tristate sda_buffer(
		//.pin(hdmi_sda),
		.pin(gpio_0_7),
		.enable(sda_enable),
		.data_out(sda_out),
		.data_in(sda_in)
	);
	reg [7:0] edid[0:255];
	reg [7:0] edid_data;
	wire [7:0] edid_read_addr;
	initial $readmemh("edid.hex", edid);

	i2c_device i2c_i(
		.clk(clk),
		.reset(reset),
		.scl_in(hdmi_scl),
		.sda_in(sda_in),
		.sda_out(sda_out),
		.sda_enable(sda_enable),

		// we only implement reads
		.data_addr(edid_read_addr),
		.rd_data(edid[edid_read_addr])
	);
endmodule
