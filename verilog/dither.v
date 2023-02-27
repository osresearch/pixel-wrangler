/*
 * Blue-Noise dithering of the HDMI signal into a 1bpp,
 * along with clock-crossing to make it usable by an externaly
 * clocked video output.
 */

module hdmi_dither(
	// inputs in the hdmi_clk domain
	input hdmi_clk,
	input hdmi_vsync,
	input [11:0] hdmi_xaddr,
	input [11:0] hdmi_yaddr,
	input hdmi_valid,
	input [7:0] hdmi_r,
	input [7:0] hdmi_g,
	input [7:0] hdmi_b,

	// outputs in the clk domain
	input mono_clk,
	output [15:0] mono_bits,
	output [11:0] mono_xaddr, // base address of the 16 bits
	output [11:0] mono_yaddr,
	output mono_bits_ready,
	output mono_vsync
);
	parameter DITHER_BITS = 6;
	parameter X_OFFSET = 64;
	parameter Y_OFFSET = 128;
	parameter WIDTH = 512;
	parameter HEIGHT = 342;

	reg [15:0] hdmi_bits;
	reg [15:0] mono_bits;

	reg bits_ready;
	reg mono_bits_ready;
	reg [11:0] mono_xaddr;
	reg [11:0] mono_yaddr;

	wire mono_vsync;

	wire vsync_falling_edge;
	edge_detect vsync_edge(hdmi_clk, hdmi_vsync, vsync_falling_edge); 

	clock_cross_strobe
		ready_strobe(hdmi_clk, bits_ready, mono_clk, mono_bits_ready);
	clock_cross_strobe
		vsync_strobe(hdmi_clk, vsync_falling_edge, mono_clk, mono_vsync);
	
	wire dither_bit;
	dither #(
		.ADDR_BITS(DITHER_BITS)
	) dither_i(
		.clk(hdmi_clk),
		.r(hdmi_r),
		.b(hdmi_b),
		.g(hdmi_g),
		.x(hdmi_xaddr[DITHER_BITS-1:0]),
		.y(hdmi_yaddr[DITHER_BITS-1:0]),
		.out(dither_bit)
	);

	wire [11:0] out_xaddr = hdmi_xaddr - X_OFFSET;
	wire [11:0] out_yaddr = hdmi_yaddr - Y_OFFSET;

	wire hdmi_in_window = 1
		&& X_OFFSET <= hdmi_xaddr && hdmi_xaddr < X_OFFSET + WIDTH
		&& Y_OFFSET <= hdmi_yaddr && hdmi_yaddr < Y_OFFSET + HEIGHT;

	wire [15:0] hdmi_bits_next = { hdmi_bits[14:0], dither_bit };

	always @(posedge hdmi_clk)
	begin
		bits_ready <= 0;

		// accumulate the hdmi bits as they come in
		// dither bit is delayed by one clock, but that's ok
		// since it just shifts the display by a pixel
		if (hdmi_valid)
			hdmi_bits <= hdmi_bits_next;

		// clock crossing flag for the full shift register
		if (hdmi_valid && out_xaddr[3:0] == 4'b0000)
		begin
			// full shift register, store the base address
			// of the X register and the bits
			// do not signal if outside of the active window
			bits_ready <= hdmi_in_window;
			mono_bits <= hdmi_bits;
			mono_xaddr <= { out_xaddr[11:4]-1, 4'b0000 };
			mono_yaddr <= out_yaddr;
		end
	end
endmodule

/*
 * Blue Noise dithering uses two block RAMs to store the 32x32x8 image
 * and thresholds the sum to determine if this pixel is black or white
 */
module dither(
	input clk,
	input [7:0] r,
	input [7:0] g,
	input [7:0] b,
	input [ADDR_BITS-1:0] x,
	input [ADDR_BITS-1:0] y,
	output out
);
	parameter ADDR_BITS = 5;
	parameter NOISE_FILE =
		ADDR_BITS == 5 ? "bluenoise-32.hex" :
		ADDR_BITS == 6 ? "bluenoise-64.hex" :
		"unknown-noise-value";

	reg [7:0] noise[0:(1 << (2*ADDR_BITS)) - 1];
	initial $readmemh(NOISE_FILE, noise);
	wire [2*ADDR_BITS-1:0] noise_addr = { x, y };
	reg [7:0] noise_value;

	reg out;

	// this may need to be adjusted once all three channels
	// are available. the plus one ensures that 255 -> 256
	// for a pure white and avoids a larger comparison in
	// the clocked block.
	//wire [9:0] sum = r + g + b + noise_value + 1;
	wire [9:0] sum = b + noise_value + 1;

	// if the sum of the red, green, blue and nosie for this
	// address is more than 255, then it is a white pixel
	always @(posedge clk)
	begin
		noise_value <= noise[noise_addr];
		out <= sum[9:8] != 0;
	end
endmodule

module clock_cross_strobe(
	input clk_in,
	input in,
	input clk_out,
	output out
);
	reg flag = 0;
	reg last_flag = 0;
	reg out = 0;

	always @(posedge clk_in)
		if (in)
			flag <= ~flag;

	always @(posedge clk_out)
	begin
		out <= last_flag != flag;
		last_flag <= flag;
	end
endmodule


module edge_detect(
	input clk,
	input in,
	output fall,
	output rise
);
	reg last;
	assign fall = !in &&  last;
	assign rise =  in && !last;
	always @(posedge clk)
		last <= in;
endmodule
