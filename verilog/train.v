/*
 * HDMI interface for the NS Train display.
 *
 * This uses the decoded data from the tmds_decoder to
 * produce pixels. It can either write them into a frame
 * buffer, or make them available as a streaming interface
 * in the hdmi_clk domain.
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
`include "tmds.v"
`include "hdmi.v"
`include "uart.v"
`include "pwm.v"
`include "i2c.v"

module top(
	output serial_txd,
	input serial_rxd,
	output spi_cs,
	output led_r,
	output led_g,
	output led_b,

	// debug output
	output gpio_28,
	output gpio_2,
	output gpio_46,

	// hdmi clock 
	input gpio_37, // pair input gpio_4,

	// hdmi pairs 36/43, 38/42, 26/27
	input gpio_43, // pair input gpio_36,
	input gpio_42, // pair input gpio_38,
	input gpio_26, // pair input gpio_27

	// hdmi i2c interface
	input gpio_23, // SCL
	inout gpio_25, // SDA

	// two LED panels
	output gpio_12,
	output gpio_21,
	output gpio_13,
	output gpio_19,
	output gpio_18,
	output gpio_11,
	output gpio_9,
	output gpio_6,
	output gpio_44
);
	assign spi_cs = 1; // it is necessary to turn off the SPI flash chip
	//reg led_r, led_g, led_b;

	reg reset = 0;
	wire clk_48mhz;
	SB_HFOSC inthosc(.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk_48mhz));
	//wire clk = clk_48mhz;
	reg [38:0] counter;
	reg clk = counter[1];
	always @(posedge clk_48mhz)
		counter <= counter + 1;

	wire panel_data1 = gpio_12;
	wire panel_latch = gpio_21;
	wire panel_clk = gpio_13;
	wire panel_en = gpio_19;
	wire panel_a3 = gpio_18;
	wire [2:0] panel_addr = { gpio_11, gpio_9, gpio_6 };
	wire panel_data0 = gpio_44;
	assign panel_a3 = 0;

	wire hdmi_clk;
	wire hdmi_bit_clk;
	wire hdmi_valid;
	wire hdmi_locked;

	wire data_valid;
	wire [7:0] d0;
	wire [7:0] d1;
	wire [7:0] d2;

	wire [1:0] hdmi_sync;
	wire hsync, vsync;
	wire rgb_valid;
	wire [7:0] r;
	wire [7:0] g;
	wire [7:0] b;
	wire [11:0] hdmi_xaddr;
	wire [11:0] hdmi_yaddr;

	reg hdmi_reset = 0;
	reg [20:0] invalid_counter = 0;
	always @(posedge clk)
	begin
		if (!hdmi_valid)
			invalid_counter <= invalid_counter + 1;
		else
			invalid_counter <= invalid_counter == 0 ? 0 : invalid_counter - 1;

		hdmi_reset <= invalid_counter[20];
		//led_b <= !hdmi_reset;
	end

	tmds_decoder tmds_decoder_i(
		.reset(hdmi_reset),

		// physical inputs
		.clk_p(gpio_37),
		.d0_p(gpio_42),
		.d1_p(gpio_43),
		.d2_p(gpio_26),

		// outputs
		.hdmi_clk(hdmi_clk),
		.bit_clk(hdmi_bit_clk),
		.hdmi_valid(hdmi_valid),
		.hdmi_locked(hdmi_locked),
		.sync(hdmi_sync),
		.d0(d0),
		.d1(d1),
		.d2(d2),
		.data_valid(data_valid)
	);

	hdmi_stream hdmi_s(
		// inputs
		.clk(hdmi_clk),
		.valid(hdmi_valid),
		.sync(hdmi_sync),
		.d0(d0),
		.d1(d1),
		.d2(d2),
		// outputs
		.xaddr(hdmi_xaddr),
		.yaddr(hdmi_yaddr),
		.vsync(vsync),
		.hsync(hsync),
		.rgb_valid(rgb_valid),
		.r(r),
		.g(g),
		.b(b)
	);

	parameter LED_PANEL_WIDTH = 104;
	parameter ADDR_WIDTH = 12;
	parameter MIN_X = 50;
	parameter MIN_Y = 110; // we aren't doing overscan correctly

	// turn the weird linear addresses from the led matrix into
	// frame buffer read addresses for the RAM.  note that both
	// framebuffers are read with the same x and y since the
	// read addresses are in fb space, not hdmi space
	wire [ADDR_WIDTH-1:0] led_addr;
	wire [11:0] led_xaddr;
	wire [11:0] led_yaddr;
	display_mapper mapper(led_addr, led_xaddr, led_yaddr);

	// outputs to the LED matrices
	wire [7:0] r0;
	wire [7:0] g0;
	wire [7:0] b0;
	wire [7:0] r1;
	wire [7:0] g1;
	wire [7:0] b1;

	// the train display has two separate LED modules,
	// so two subsections of the frame buffer are used
	// the modules aren't 128 across, but for simplicity
	// the overlapping bits are stored here anyway
	hdmi_framebuffer #(
		.MIN_X(MIN_X + 0*LED_PANEL_WIDTH),
		.MIN_Y(MIN_Y),
		.WIDTH(128),
		.HEIGHT(32),
	) fb0(
		// hdmi side
		.hdmi_clk(hdmi_clk),
		.xaddr(hdmi_xaddr),
		.yaddr(hdmi_yaddr),
		.rgb_valid(rgb_valid),
		.r(r),
		.g(g),
		.b(b),
		// output side
		.clk(clk),
		.xaddr_r(led_xaddr),
		.yaddr_r(led_yaddr),
		.r_out(r0),
		.g_out(g0),
		.b_out(b0)
	);

	hdmi_framebuffer #(
		.MIN_X(MIN_X + 1*LED_PANEL_WIDTH),
		.MIN_Y(MIN_Y),
		.WIDTH(128),
		.HEIGHT(32),
	) fb1(
		// hdmi side
		.hdmi_clk(hdmi_clk),
		.rgb_valid(rgb_valid),
		.xaddr(hdmi_xaddr),
		.yaddr(hdmi_yaddr),
		.r(r),
		.g(g),
		.b(b),
		// output side
		.clk(clk),
		.xaddr_r(led_xaddr),
		.yaddr_r(led_yaddr),
		.r_out(r1),
		.g_out(g1),
		.b_out(b1)
	);

	led_matrix #(
		// internal display 4 address lines, 32 * 128
		//.DISP_ADDR_WIDTH(4),
		//.DISPLAY_WIDTH(13'd384), // 24 * 16
		// external display is 3 address lines, 32 * 104
		.DISP_ADDR_WIDTH(3),
		.DISPLAY_WIDTH(416), // 13 columns * 16 * 2
		.FB_ADDR_WIDTH(ADDR_WIDTH)
	) disp0(
		.clk(clk),
		.reset(reset),
		// physical interface
		.data_out(panel_data0), // gpio_34),
		.clk_out(panel_clk), // gpio_26),
		.latch_out(panel_latch), // gpio_25),
		.enable_out(panel_en), // gpio_27),
		.addr_out(panel_addr), // outside panel has 3 address bits
		// logical interface
		.data_in(b0),
		.data_addr(led_addr)
	);

	led_matrix #(
		// internal display 4 address lines, 32 * 128
		//.DISP_ADDR_WIDTH(4),
		//.DISPLAY_WIDTH(13'd384), // 24 * 16
		// external display is 3 address lines, 32 * 104
		.DISP_ADDR_WIDTH(3),
		.DISPLAY_WIDTH(416), // 26 * 16 * 2
		.FB_ADDR_WIDTH(ADDR_WIDTH)
	) disp1(
		.clk(clk),
		.reset(reset),
		// physical interface (only data is used)
		.data_out(panel_data1), // gpio_23),
		// logical interface
		.data_in(b1),
		//.data_addr(read_addr)
	);

	// EDID interface
	wire sda_pin = gpio_25;
	wire scl_pin = gpio_23;
	wire sda_out;
	wire sda_in;
	wire sda_enable;

	//assign gpio_2 = scl_pin;
	//assign gpio_28 = sda_in;
	//assign gpio_46 = sda_enable;

/*
	wire uart_txd_strobe;
	wire [7:0] uart_txd;
	uart uart_i(
		.clk_48mhz(clk_48mhz),
		.clk(clk),
		.reset(reset),
		.serial_txd(serial_txd),
		.uart_txd(uart_txd),
		.uart_txd_strobe(uart_txd_strobe)
	);
*/

	tristate scl(
		.pin(sda_pin),
		.enable(sda_enable),
		.data_out(sda_out),
		.data_in(sda_in)
	);
	reg [7:0] edid[0:255];
	reg [7:0] edid_data;
	wire [7:0] edid_read_addr;
	initial $readmemh("edid.hex", edid);
	always @(posedge clk)
		edid_data <= edid[edid_read_addr];

	i2c_device i2c_i(
		.clk(clk),
		.reset(reset),
		.scl_in(scl_pin),
		.sda_in(sda_in),
		.sda_out(sda_out),
		.sda_enable(sda_enable),

		// we only implement reads
		.data_addr(edid_read_addr),
		.rd_data(edid[edid_read_addr])
	);

	wire [7:0] rate_r = 8'h0F;
	wire [7:0] rate_g = 8'h1F;
	wire [7:0] rate_b = 8'h3F;

	wire [7:0] bright_r;
	wire [7:0] bright_g;
	wire [7:0] bright_b;
	breath breath_r(clk, rate_r, bright_r);
	breath breath_g(clk, rate_g, bright_g);
	breath breath_b(clk, rate_b, bright_b);

	rgb_drv rgb_drv_i(
		.clk(clk),
		.enable(1),
		.out({led_r,led_g,led_b}),
		.bright_r(bright_r),
		.bright_g(bright_g),
		.bright_b(bright_b)
	);

	//reg gpio_2, gpio_28;
	assign gpio_2 = hdmi_locked;
	assign gpio_28 = hdmi_valid;
	assign gpio_46 = vsync;

	always @(posedge hdmi_clk)
	begin
/*
		if (hdmi_valid)
		begin
			bright_g <= 20;
			bright_r <= 0;
		end else begin
			bright_g <= 0;
			bright_r <= 20;
		end
*/
	end
endmodule

module tristate(
	inout pin,
	input enable,
	input data_out,
	output data_in
);
	SB_IO #(
		.PIN_TYPE(6'b1010_01) // tristatable output
	) buffer(
		.PACKAGE_PIN(pin),
		.OUTPUT_ENABLE(enable),
		.D_IN_0(data_in),
		.D_OUT_0(data_out)
	);
endmodule



// for speed of receiving the HDMI signals, the framebuffer is stored in
// normal layout with a power-of-two pitch.
// the actual LED matrix might be weird, so turn a linear offset
// into a framebuffer offset.
//
// external display is 104 wide 32 high, but mapped like:
//
// 10 skip eight    30 repeat 13 times 190
// |           \    |                  |
// 1f           \   3f                 19f -> go back to second column
// 00 1a0        \->20                 180
// |  |             |                  |
// 0f 1af           2f                 18f
// 

module display_mapper(
	input [12:0] linear_addr,
	output [11:0] x_addr,
	output [4:0] y_addr
);
	parameter PANEL_SHIFT_WIDTH = (13 * 32) / 32;
	parameter PANEL_PITCH = 128;

	wire y_bank = linear_addr[4];

	wire [12:0] x_value = linear_addr[12:5];
	wire [12:0] x_offset;
	reg [2:0] x_minor;
	reg [12:0] x_major;

	wire [4:0] y_addr = linear_addr[3:0] + (y_bank ? 0 : 16);
	wire [11:0] x_addr = x_major*8 + x_minor;

	always @(*)
	begin
		if (x_value >= 7 * PANEL_SHIFT_WIDTH) begin
			x_minor = 7;
			x_major = x_value - 7 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 6 * PANEL_SHIFT_WIDTH) begin
			x_minor = 6;
			x_major = x_value - 6 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 5 * PANEL_SHIFT_WIDTH) begin
			x_minor = 5;
			x_major = x_value - 5 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 4 * PANEL_SHIFT_WIDTH) begin
			x_minor = 4;
			x_major = x_value - 4 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 3 * PANEL_SHIFT_WIDTH) begin
			x_minor = 3;
			x_major = x_value - 3 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 2 * PANEL_SHIFT_WIDTH) begin
			x_minor = 2;
			x_major = x_value - 2 * PANEL_SHIFT_WIDTH;
		end else
		if (x_value >= 1 * PANEL_SHIFT_WIDTH) begin
			x_minor = 1;
			x_major = x_value - 1 * PANEL_SHIFT_WIDTH;
		end else begin
			x_minor = 0;
			x_major = x_value;
		end
	end
endmodule


module led_matrix(
	input clk,
	input reset,
	// physical
	output data_out,
	output clk_out,
	output latch_out,
	output enable_out,
	output [DISP_ADDR_WIDTH-1:0] addr_out,
	// framebuffer
	output [FB_ADDR_WIDTH-1:0] data_addr,
	input [DATA_WIDTH-1:0] data_in
);
	parameter DISP_ADDR_WIDTH = 4;
	parameter DISPLAY_WIDTH = 32;
	parameter FB_ADDR_WIDTH = 8;
	parameter DATA_WIDTH = 8;

	reg clk_out;
	reg latch_out;
	reg data_out;
	reg enable_out;
	reg [DISP_ADDR_WIDTH-1:0] addr_out;
	reg [DISP_ADDR_WIDTH-1:0] addr;

	reg [FB_ADDR_WIDTH-1:0] x_index;
	reg [FB_ADDR_WIDTH-1:0] data_addr;

	reg [FB_ADDR_WIDTH-1:0] counter;
	reg [30:0] counter_timer;

	// usable brightness values start around 0x40
	reg [2:0] latch_counter = 0;
	reg [7:0] brightness = 8'hFF;

	always @(posedge clk)
	begin
		clk_out <= 0;

		counter_timer <= counter_timer + 1;
		enable_out <= !(brightness > counter_timer[7:0]);

		if (reset)
		begin
			counter <= 0;
			enable_out <= 1;
			data_addr <= ~0;
			x_index <= 0;
			addr_out <= 0;
			addr <= 0;
			data_out <= 0;
			latch_counter <= 0;
			brightness <= 8'h80;
		end else
		if (latch_out)
		begin
			// unlatch and re-enable the display
			latch_out <= 0;
			//enable_out <= 0;

			// if this has wrapped the display,
			// start over on reading the frame buffer
			if (addr == 0)
				data_addr <= 0;
			// hold the clock high
			clk_out <= 1;
		end else
		if (x_index == DISPLAY_WIDTH)
		begin
			if (latch_counter == 7)
			begin
				// done with this scan line, reset for the next time
				addr <= addr + 1;
				brightness <= 8'hFF; // last one, so make it bright
			end else begin
				// redraw the same scan line a few times at different brightness levels
				data_addr <= data_addr - DISPLAY_WIDTH;
				brightness <= brightness + 8'h18;
			end

			// latch this data and ensure that the correct matrix row is selected
			latch_out <= 1;
			addr_out <= addr;
			latch_counter <= latch_counter + 1;

			// start a new scan line
			x_index <= 0;
			// hold the clock high
			clk_out <= 1;
		end else
		if (clk_out == 1)
		begin
			// falling edge of the clock, prepare the next output
			// use binary-coded pulse modulation, so turn on the output
			// based on each bit and the current brightness level
			if (data_in[latch_counter])
			//if (data_in)
				data_out <= 1;
			else
				data_out <= 0;

			x_index <= x_index + 1;

			// start the fetch for the next address
			data_addr <= data_addr + 1;
		end else begin
			// rising edge of the clock, new data should be ready
			// and stable, so mark it
			clk_out <= 1;
		end
	end
endmodule
