/*
 * Decode the TMDS and TERC4 encoded data in the HDMI stream.
 * Only Channel 0 (Blue) has the synchronization bits and the
 * TERC4 data during the data island period.
 */
/*
 5.4.2 control period coding:
the three TMDS channels are encoded as follows:
D0 = hsync, D1 = vsync
case (D1, D0):
 0, 0: q_out[9:0] = 0b1101010100;
 0, 1: q_out[9:0] = 0b0010101011;
 1, 0: q_out[9:0] = 0b0101010100;
 1, 1: q_out[9:0] = 0b1010101011;
endcase; 
*/

module tmds_decode(
	input clk,
	input [9:0] in,
	output data_valid,
	output sync_valid,
	output ctrl_valid,
	output [7:0] data,
	output [1:0] sync, // hsync/vsync
	output [3:0] ctrl  // audio header?
);
	// the sync control bits are encoded with four specific patterns
	parameter CTRL_00 = 10'b1101010100; // 354
	parameter CTRL_01 = 10'b0010101011; // 0AB
	parameter CTRL_10 = 10'b0101010100; // 154
	parameter CTRL_11 = 10'b1010101011; // 2AB

	// the control channel data
	parameter TERC4_0 = 10'b1010011100;
    	parameter TERC4_1 = 10'b1001100011;
    	parameter TERC4_2 = 10'b1011100100;
    	parameter TERC4_3 = 10'b1011100010;
    	parameter TERC4_4 = 10'b0101110001;
    	parameter TERC4_5 = 10'b0100011110;
    	parameter TERC4_6 = 10'b0110001110;
    	parameter TERC4_7 = 10'b0100111100;
    	parameter TERC4_8 = 10'b1011001100;
    	parameter TERC4_9 = 10'b0100111001;
    	parameter TERC4_A = 10'b0110011100;
    	parameter TERC4_B = 10'b1011000110;
    	parameter TERC4_C = 10'b1010001110;
    	parameter TERC4_D = 10'b1001110001;
    	parameter TERC4_E = 10'b0101100011;
    	parameter TERC4_F = 10'b1011000011;

	// first two of the 10 bits encodes the how the other bits
	// are encoded (either inverted and either xor or xnor)
	// see page 83 of HDMI 1.3 spec
	wire invert = in[9];
	wire use_xor = in[8];

	wire [7:0] in_bits = invert ? ~in[7:0] : in;
	wire [7:0] in_xor = { in_bits[6:0] ^ in_bits[7:1], in_bits[0] };
	wire [7:0] in_xnor = { in_bits[6:0] ^~ in_bits[7:1], in_bits[0] };
	wire [7:0] data_out = use_xor ? in_xor : in_xnor;

	reg data_valid;
	reg sync_valid;
	reg ctrl_valid;
	reg [7:0] data;
	reg [1:0] sync;
	reg [3:0] ctrl;

	always @(posedge clk)
	begin
		sync_valid <= 0;
		ctrl_valid <= 0;
		data_valid <= 0;

		data <= data_out;

		case(in)
		CTRL_00: { sync_valid, sync } = { 1'b1, 2'b00 };
		CTRL_01: { sync_valid, sync } = { 1'b1, 2'b01 };
		CTRL_10: { sync_valid, sync } = { 1'b1, 2'b10 };
		CTRL_11: { sync_valid, sync } = { 1'b1, 2'b11 };

		TERC4_0: { ctrl_valid, ctrl } = { 1'b1, 4'h0 };
		TERC4_1: { ctrl_valid, ctrl } = { 1'b1, 4'h1 };
		TERC4_2: { ctrl_valid, ctrl } = { 1'b1, 4'h2 };
		TERC4_3: { ctrl_valid, ctrl } = { 1'b1, 4'h3 };
		TERC4_4: { ctrl_valid, ctrl } = { 1'b1, 4'h4 };
		TERC4_5: { ctrl_valid, ctrl } = { 1'b1, 4'h5 };
		TERC4_6: { ctrl_valid, ctrl } = { 1'b1, 4'h6 };
		TERC4_7: { ctrl_valid, ctrl } = { 1'b1, 4'h7 };
		TERC4_8: { ctrl_valid, ctrl } = { 1'b1, 4'h8 };
		TERC4_9: { ctrl_valid, ctrl } = { 1'b1, 4'h9 };
		TERC4_A: { ctrl_valid, ctrl } = { 1'b1, 4'hA };
		TERC4_B: { ctrl_valid, ctrl } = { 1'b1, 4'hB };
		TERC4_C: { ctrl_valid, ctrl } = { 1'b1, 4'hC };
		TERC4_D: { ctrl_valid, ctrl } = { 1'b1, 4'hD };
		TERC4_E: { ctrl_valid, ctrl } = { 1'b1, 4'hE };
		TERC4_F: { ctrl_valid, ctrl } = { 1'b1, 4'hF };

		default:
			data_valid <= 1;
		endcase
/*
		if (in == CTRL_00) { sync_valid, sync } = { 1'b1, 2'b00 }; else
		if (in == CTRL_01) { sync_valid, sync } = { 1'b1, 2'b01 }; else
		if (in == CTRL_10) { sync_valid, sync } = { 1'b1, 2'b10 }; else
		if (in == CTRL_11) { sync_valid, sync } = { 1'b1, 2'b11 }; else
		data_valid <= 1;
*/
	end
endmodule
