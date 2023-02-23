/*
 * HDMI interface for a classic Mac
 *
 */
`default_nettype none
`define WRANGLER_LED
`include "top.v"
`include "dither.v"

module display(
	input clk_48mhz,
	input clk, // system clock, probably 12 or 24 Mhz

	// Streaming HDMI interface (in 25 MHz hdmi_clk domain)
	input hdmi_clk,
	input hdmi_valid,
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
	wire reset = 0;

	// pulse the RGB led. should do something with state here
	wire [7:0] rate_r = 8'h0F;
	wire [7:0] rate_g = 8'h1F;
	wire [7:0] rate_b = 8'h3F;

	breath breath_r(clk, rate_r, led_r);
	breath breath_g(clk, rate_g, led_g);
	breath breath_b(clk, rate_b, led_b);

	// produce a 16 MHz clock from the 48 Mhz clock
	wire clk_16mhz;
	clk_div3 div3(clk_48mhz, reset, clk_16mhz);

	wire [9:0] fb_xaddr;
	wire [8:0] fb_yaddr;
	reg [7:0] fb[0:1023];
	initial $readmemh("apple-32.hex", fb);
	wire [9:0] fb_addr = { fb_yaddr[6:2], fb_xaddr[6:2] };
	wire fb_data = fb[fb_addr] > 127;

	mac_display crt(
		.clk_16mhz(clk_16mhz),
		.reset(reset),
		.hsync(gpio_bank_1[1]),
		.vsync(gpio_bank_1[2]),
		.out(gpio_bank_1[0]),
		.xaddr(fb_xaddr),
		.yaddr(fb_yaddr),
		.fb_data(fb_data)
	);

/*
	wire [15:0] mono_bits;
	wire [11:0] mono_xaddr;
	wire [11:0] mono_yaddr;
	wire mono_bits_ready;
	wire mono_vsync;

	// todo: window the X and Y addresses!
	hdmi_dither dither(
		.hdmi_clk(hdmi_clk),
		.hdmi_valid(hdmi_valid && rgb_valid),
		.hdmi_vsync(vsync),
		.hdmi_xaddr(hdmi_xaddr),
		.hdmi_yaddr(hdmi_yaddr),
		.hdmi_r(r),
		.hdmi_r(g),
		.hdmi_r(b),

		.mono_clk(clk_16mhz),
		.mono_bits(mono_bits),
		.mono_xaddr(mono_xaddr),
		.mono_yaddr(mono_yaddr),
		.mono_bits_ready(mono_bits_ready),
		.mono_vsync(mono_vsync)
	);
	

	reg fb_xaddr[8:0];
	reg fb_yaddr[8:0];

	wire [12:0] rd_addr = fb_xaddr[8:4] | (fb_yaddr[8:0] << 5);

	reg mono_bits_ready_delay = 0;

	wire reader_active = draw_active && fb_xaddr[4:0] == 4b'1111;

	wire fb_wen = !reader_active && (mono_bits_ready || mono_bits_ready_delay);

	// xaddr bottom 4 bits are all zero since there are 16-bits
	// returned at a time.  xaddr only goes to 512, so we have
	// only a few bits worth of 
	wire [12:0] wd_addr = mono_xaddr[8:4] | (mono_yaddr[8:0] << 5);

	// 512x512x1 fits in a single ice40up5k SPRAM
	spram framebuffer(
		.clk(clk_16mhz),
		.wen(fb_wen),
		.wr_addr(wd_addr),
		.wr_data(mono_bits),
		.rd_add(rd_addr),
		.rd_data(fb_bits)
	);
*/

endmodule


module mac_display(
	input reset,
	input clk_16mhz,
	output [9:0] xaddr,
	output [8:0] yaddr,
	input fb_data,
	output vsync,
	output hsync,
	output out
);
	parameter ACTIVE_WIDTH = 512;
	parameter ACTIVE_HEIGHT = 342;
	parameter ACTIVE_XOFFSET = 190;
	parameter ACTIVE_YOFFSET = 48;

	parameter TOTAL_WIDTH = 720;
	parameter TOTAL_HEIGHT = ACTIVE_HEIGHT + ACTIVE_YOFFSET; //384;
	parameter VSYNC_LINES = 6; // how many hsyncs during vsync low
	parameter VSYNC_OFFSET = 128; // edge of vsync relative to hsync
	parameter HSYNC_OFFSET = 294; // rising edge of the hsync line

	reg hsync;
	reg vsync;
	reg out;

	reg [9:0] xscan;
	reg [8:0] yscan;
	wire [9:0] xaddr = xscan - ACTIVE_XOFFSET;
	wire [8:0] yaddr = yscan - ACTIVE_YOFFSET;
	wire in_active_window = 1
		&& xaddr < ACTIVE_WIDTH
		&& yaddr < ACTIVE_HEIGHT;

	always @(posedge clk_16mhz)
	if (reset)
	begin
		xscan <= 0;
		yscan <= 0;
		vsync <= 1;
		hsync <= 1;
	end else begin
		// 45 usec per hsync * 16 MHz == 720 total X addresses
		// = 180 hsync + 512 active + 28?
		// vsync offset from hsync
		xscan <= xscan + 1;
		if (xscan == TOTAL_WIDTH-1)
		begin
			xscan <= 0;

			if (yscan == TOTAL_HEIGHT-1)
				yscan <= 0;
			else
				yscan <= yscan + 1;
		end

		if (yscan == 0 && xscan == VSYNC_OFFSET)
			vsync <= 0;
		else
		if (yscan == VSYNC_LINES && xscan == VSYNC_OFFSET)
			vsync <= 1;

		if (xscan == 0)
			hsync <= 0;
		else
		if (xscan == HSYNC_OFFSET)
			hsync <= 1;

		if (in_active_window)
			out <= ~fb_data;
		else
			out <= 1; // idle high
	end
endmodule

module clk_div3(
	input clk,
	input reset,
	output clk_out
);
	reg [1:0] pos_count, neg_count;
	assign clk_out = (pos_count == 2) || (neg_count == 2);
 
	always @(posedge clk)
	if (reset || pos_count == 2)
		pos_count <= 0;
	else
		pos_count <= pos_count + 1;

	always @(negedge clk)
	if (reset || neg_count == 2)
		neg_count <= 0;
	else
		neg_count <= neg_count + 1;
 
endmodule
