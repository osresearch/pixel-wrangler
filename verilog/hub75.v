/*
 * HDMI interface for a "Hub75" LED matrix
 *
 * The test one is weird: 64x32, but single scan with five address lines
 *
 * This easily fits in the DPRAM so no fancy clocking is required.
 *
 */
`default_nettype none
`define WRANGLER_LED
`define WRANGLER_SWITCH
`include "top.v"

module display(
	input clk_48mhz,
	input clk, // system clock, probably 12 or 24 Mhz
	input sw1, // user switch
	input reset,

	// Streaming HDMI interface (in 25 MHz hdmi_clk domain)
	input hdmi_clk,
	input hdmi_bit_clk,
	input hdmi_valid,
	input hdmi_reset,
	output hdmi_user_reset,
	input vsync,
	input hsync,
	input rgb_valid,
	input [7:0] r,
	input [7:0] g,
	input [7:0] b,
	input [11:0] hdmi_xaddr,
	input [11:0] hdmi_yaddr,

	// GPIO banks for output
	output [7:0] gpio_bank_0,
	output [7:0] gpio_bank_1,

	// RGB led on the board with PWM
	output [7:0] led_r,
	output [7:0] led_g,
	output [7:0] led_b
);
	assign hdmi_user_reset = !sw1;

	// pulse the RGB led. shinputould do something with state here
	assign led_r = hdmi_reset ? 8'hFF : 8'h00;
	assign led_g = rgb_valid ? 8'h30 : 8'h00;
	assign led_b = hdmi_reset ? 8'hFF : 8'h00;

	parameter X_OFFSET = 64;
	parameter Y_OFFSET = 128;
	parameter X_BITS = 6; // log2(WIDTH)
	parameter Y_BITS = 5; // log2(HEIGHT)
	parameter WIDTH = 1 << X_BITS;
	parameter HEIGHT = 1 << Y_BITS;
	parameter ADDR_PINS = 5; // single scan display, so same as Y_BITS

	reg [X_BITS-1:0] xaddr;
	reg [Y_BITS-1:0] yaddr;

	reg clk_24mhz = 0;
	always @(posedge clk_48mhz)
		clk_24mhz <= ~clk_24mhz;

	wire [7:0] r_out, g_out, b_out;

	// for a dual scan display we would need two framebuffers
	hdmi_framebuffer #(
		.WIDTH(WIDTH),
		.HEIGHT(HEIGHT),
		.MIN_X(X_OFFSET),
		.MIN_Y(Y_OFFSET),
		.ADDR_WIDTH(X_BITS + Y_BITS) // log(WIDTH*HEIGHT)
	) fb(
		// HDMI interface
		.hdmi_clk(hdmi_clk),
		.xaddr(hdmi_xaddr),
		.yaddr(hdmi_yaddr),
		.rgb_valid(rgb_valid),
		.r(r),
		.g(g),
		.b(b),
		// Reader interface
		.clk(clk_48mhz),
		.xaddr_r(xaddr),
		.yaddr_r(yaddr),
		.r_out(r_out),
		.g_out(g_out),
		.b_out(b_out)
	);

	wire [10:0] r_gamma;
	wire [10:0] b_gamma;
	wire [10:0] g_gamma;
	gamma gamma_r(clk_24mhz, r_out, r_gamma);
	gamma gamma_g(clk_24mhz, g_out, g_gamma);
	gamma gamma_b(clk_24mhz, b_out, b_gamma);

	hub75 #(
		.DEPTH(11),
		.X_BITS(X_BITS),
		.Y_BITS(Y_BITS),
		.ADDR_PINS(ADDR_PINS)
	) hub_display(
		// framebuffer
		.xaddr(xaddr),
		.yaddr(yaddr),
		.r_in(r_gamma),
		.g_in(g_gamma),
		.b_in(b_gamma),

		// output
		.reset(reset),
		.clk(clk_24mhz),
		.clk_pwm(clk_48mhz),
		.enable_n(gpio_bank_1[0]),
		.led_clk(gpio_bank_1[1]),
		.latch(gpio_bank_1[2]),
		.r_out(gpio_bank_1[3]),
		.g_out(gpio_bank_1[4]),
		.b_out(gpio_bank_1[5]),
		.led_addr(gpio_bank_0[ADDR_PINS-1:0])
	);
endmodule

module gamma(
	input clk,
	input [7:0] linear,
	output [10:0] log
);
	parameter GAMMA="2.8";
	reg [15:0] gamma_table[0:255];
	reg [4:0] low_bits;
	initial $readmemh({"gamma.",GAMMA,".hex"}, gamma_table);
	always @(posedge clk)
		{ log, low_bits } <= gamma_table[linear];
endmodule

module hub75(
	input reset,
	input clk,
	input clk_pwm,

	// framebuffer
	output [X_BITS-1:0] xaddr,
	output [Y_BITS-1:0] yaddr,
	input [DEPTH-1:0] r_in,
	input [DEPTH-1:0] g_in,
	input [DEPTH-1:0] b_in,

	// LED display
	output led_clk,
	output latch,
	output enable_n,
	output r_out,
	output g_out,
	output b_out,
	output [ADDR_PINS-1:0] led_addr
);
	parameter DEPTH = 8;
	parameter X_BITS = 6;
	parameter Y_BITS = 5;
	parameter ADDR_PINS = 5;

	reg [X_BITS-1:0] xaddr;
	reg [Y_BITS-1:0] yaddr;

	reg led_clk = 0;
	reg enable_n = 1;
	reg latch = 0;
	reg r_out = 0;
	reg g_out = 0;
	reg b_out = 0;
	reg [ADDR_PINS-1:0] led_addr = 0;

	reg [1:0] phase = 0;
	reg [3:0] bright_bit = 9;
	reg drain_scanline = 0;

	// the off timer includes the phase counter for one extra bit of precision
	reg [X_BITS:0] off_time = 0;
	wire [X_BITS:0] timer = { xaddr, ~phase[0] };

	reg output_enable = 1;
	reg [DEPTH-1:0] brightness = 0;
	reg [DEPTH-1:0] pwm = 0;
	reg carry = 0;
	always @(posedge clk_pwm)
	begin
/*
		if (latch)
		begin
			carry <= 0;
			pwm <= 0;
		end else
			{ carry, pwm } <= pwm + brightness;
		enable_n <= ~(output_enable && carry);
*/
		pwm <= latch ? 0 : pwm + 3;
		enable_n <= ~(output_enable && pwm < brightness);
	end

	// phase 0: clock is low, update rgb pins
	// phase 1: clock goes high, no pin changes
	// phase 2: clock goes low, no pin changes
	// phase 3: latch goes high

	always @(posedge clk)
	if (reset)
	begin
		phase <= 0;
		xaddr <= 0;
		yaddr <= 0;
		led_addr <= 0;
		//enable_n <= 1;
		led_clk <= 0;
		latch <= 0;
		r_out <= 0;
		g_out <= 0;
		b_out <= 0;
		bright_bit <= DEPTH-1;
		drain_scanline <= 0;
		off_time <= 0;
	end else
	if(phase == 2'b00)
	begin
		output_enable <= 1;
		latch <= 0;
		led_clk <= 0;

		r_out <= drain_scanline ? 0 : r_in[bright_bit];
		g_out <= drain_scanline ? 0 : g_in[bright_bit];
		b_out <= drain_scanline ? 0 : b_in[bright_bit];

		phase <= 1;
		xaddr <= xaddr + 1;

/*
		// if latch is set, this means we have just finished
		// clocking out a display. turn on the output enable (negative logic)
		if (latch)
			enable_n <= 0;

		// if we have clocked out a few pixels, turn off the display
		//if (timer == off_time)
		if (timer == off_time)
			enable_n <= 1;
*/

	end else
	if (phase == 2'b01)
	begin
		// clock goes high, no other changes
		led_clk <= 1;

/*
		// turn off the LEDs if we have hit our timer
		if (timer == off_time)
			enable_n <= 1;
*/

		// when we hit the end of the display
		if (xaddr == 0)
			phase <= 3;
		else
			phase <= 0;
		phase <= 2;
	end else
	if (phase == 2'b10)
	begin
		// clock goes low, no other changes
		led_clk <= 0;

		// when we hit the end of the display
		if (xaddr == 0)
			phase <= 3;
		else
			phase <= 0;
	end else
	if (phase == 3'b11)
	begin
		// entire row has been shifted out, turn off the display
		// and latch the new row
		output_enable <= 0;
		latch <= 1;
		phase <= 0;
		xaddr <= 0;

		// be sure that we've turned off the output
		//enable_n <= 1;

		// update the off time for the current brightness
		off_time <=
			bright_bit == 7 ?  127 :
			bright_bit == 6 ?   64 :
			bright_bit == 5 ?   32 :
			bright_bit == 4 ?   16 :
			bright_bit == 3 ?    8 :
			bright_bit == 2 ?    4 :
			bright_bit == 1 ?    2 :
			bright_bit == 0 ?    1 :
			8;

		brightness <= (1 << bright_bit) - 1;

		// make sure the correct output line is selected
		// this is the row that we just output
		led_addr <= yaddr[ADDR_PINS-1:0];


		if (drain_scanline)
		begin
			// hold the drained scanline for a while
			brightness <= 10'h3FF;
			off_time <= 100;

			// move to the next bit on the BCM output
			yaddr <= yaddr + 1;
			drain_scanline <= 0;
			bright_bit <= DEPTH-1;
		end else begin
			bright_bit <= bright_bit - 1;

			// after all of the brightness levels have been sent,
			// draw an empty scanline to try to prevent ghosting
			if (bright_bit == 0)
			begin
				drain_scanline <= 1;
			end
		end
	end
endmodule
