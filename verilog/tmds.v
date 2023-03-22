/* TMDS interface and decoder.
 *
 * Instantiate a tmds_decoder with the four differential pairs
 * as inputs and receives as outputs the pixel clock, three data
 * channels, and video sync signals.
 *
 * Optionally there is a locked signal for when the video is
 * detected and the 10X (or 5X with DDR) bit clock.
 *
 * Audio and other TERC4 data is not yet handled.
 */

/*
 * Decode the TMDS and TERC4 encoded data in the HDMI stream.
 * This processes pixels in the HDMI TMDS clock domain.
 *
 * Only Channel 0 (Blue) has the synchronization bits and the
 * TERC4 data during the data island period.
 */
`define TMDS_DDR

`ifdef TMDS_DDR
`include "hdmi_pll_ddr.v"
`else
`include "hdmi_pll.v"
`endif

`include "dpram.v"

module tmds_8b10b_decoder(
	input hdmi_clk,
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

	always @(posedge hdmi_clk)
	begin
		sync_valid <= 0;
		ctrl_valid <= 0;
		data_valid <= 0;

		data <= data_out;

		case(in)
		CTRL_00: { sync_valid, sync } <= { 1'b1, 2'b00 };
		CTRL_01: { sync_valid, sync } <= { 1'b1, 2'b01 };
		CTRL_10: { sync_valid, sync } <= { 1'b1, 2'b10 };
		CTRL_11: { sync_valid, sync } <= { 1'b1, 2'b11 };

		TERC4_0: { ctrl_valid, ctrl } <= { 1'b1, 4'h0 };
		TERC4_1: { ctrl_valid, ctrl } <= { 1'b1, 4'h1 };
		TERC4_2: { ctrl_valid, ctrl } <= { 1'b1, 4'h2 };
		TERC4_3: { ctrl_valid, ctrl } <= { 1'b1, 4'h3 };
		TERC4_4: { ctrl_valid, ctrl } <= { 1'b1, 4'h4 };
		TERC4_5: { ctrl_valid, ctrl } <= { 1'b1, 4'h5 };
		TERC4_6: { ctrl_valid, ctrl } <= { 1'b1, 4'h6 };
		TERC4_7: { ctrl_valid, ctrl } <= { 1'b1, 4'h7 };
		TERC4_8: { ctrl_valid, ctrl } <= { 1'b1, 4'h8 };
		TERC4_9: { ctrl_valid, ctrl } <= { 1'b1, 4'h9 };
		TERC4_A: { ctrl_valid, ctrl } <= { 1'b1, 4'hA };
		TERC4_B: { ctrl_valid, ctrl } <= { 1'b1, 4'hB };
		TERC4_C: { ctrl_valid, ctrl } <= { 1'b1, 4'hC };
		TERC4_D: { ctrl_valid, ctrl } <= { 1'b1, 4'hD };
		TERC4_E: { ctrl_valid, ctrl } <= { 1'b1, 4'hE };
		TERC4_F: { ctrl_valid, ctrl } <= { 1'b1, 4'hF };

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


/*
 * Differential input with latches on both posiive and negative edge
 * of the clock.  Converting them to the same domain is your problem.
 */
module lvds_ddr_input(
	input clk,
	input in_p,
	output [1:0] out
);
	wire [1:0] in;

	SB_IO #(
`ifdef TMDS_DDR
		.PIN_TYPE(6'b0000_00), // DDR input
`else
		.PIN_TYPE(6'b0000_11), // latched and registered at the pin
`endif
		.IO_STANDARD("SB_LVDS_INPUT")
	) diff_io (
		.PACKAGE_PIN(in_p),
		.INPUT_CLK(clk),
		.D_IN_0(in[0]), // pos edge of bit_clk
`ifdef TMDS_DDR
		.D_IN_1(in[1])  // neg edge of bit_clk
`endif
	);

`define BUFFER_LVDS
`ifdef BUFFER_LVDS
	// ensuring that there is a registered copy seems to produce better
	// timing results than directly using the one in the pin
	reg [1:0] out;
	always @(posedge clk)
		out[0] <= ~in[0];
	always @(negedge clk)
		out[1] <= ~in[1];
`else
	assign out = in;
`endif

endmodule


/*
 * Setup a 5X PLL for the hdmi clock that feeds into a global buffer
 */
module tmds_clk_pll(
	input reset,
	input clk_p,
	output hdmi_clk,
	output bit_clk,
	output locked,
	input [4:0] phase_shift = 0 // ones-complement signed
);
	SB_GB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) differential_clock_input (
		.PACKAGE_PIN(clk_p),
		.GLOBAL_BUFFER_OUTPUT(hdmi_clk)
	);

	wire [3:0] delay = phase_shift[4] ? phase_shift[3:0] : 4'b0;
	wire [3:0] advance = phase_shift[4] ? 4'b0 : ~phase_shift[3:0];

	hdmi_pll #(.DELAY(10), .ADVANCE(0))
	pll(
		.clock_in(hdmi_clk),
		.clock_out(bit_clk),
		.locked(locked),
		.reset(reset),
		.delay({delay,advance})
	);
endmodule


/*
 * Configure the inputs and setup the PLL
 * for the DDR PHY to receive two bits at a time from
 * each of the three channels.
 */
module tmds_ddr_phy(
	input reset,
	input clk_p,
	input d0_p,
	input d1_p,
	input d2_p,
	input [4:0] phase_shift = 0,
	output bit_clk,
	output hdmi_clk,
	output hdmi_locked,
	output [1:0] d0_raw,
	output [1:0] d1_raw,
	output [1:0] d2_raw
);
	wire hdmi_clk_raw; // unused since we resynth our own clock

	tmds_clk_pll tmds_clk_pll_i(
		.reset(reset || phase_reset),
		.clk_p(clk_p),
		.hdmi_clk(hdmi_clk_raw),
		.bit_clk(bit_clk),
		.locked(hdmi_locked),
		.phase_shift(phase_shift)
	);

	// re-synthesize the HDMI clock from the PLL'ed clock
	// so that it is precisely in phase to avoid CDC issues
	reg [3:0] clk_div = 0;
`ifdef TMDS_DDR
	wire clk_overflow = (clk_div == 4'h4);
`else
	wire clk_overflow = (clk_div == 4'h9);
`endif

/*
	reg hdmi_clk;
	always @(posedge bit_clk)
	begin
		clk_div <= clk_div + 1;
		hdmi_clk <= clk_div == 4'b0000;

		if (clk_overflow)
			clk_div <= 0;
	end
*/
	assign hdmi_clk = hdmi_clk_raw;

	reg phase_reset = 0;
`ifdef 0
	reg [20:0] error_count = 0;
	always @(posedge hdmi_clk_raw)
	begin
/*
		if (phase_reset)
		begin
			error_count <= error_count - 7;
			if (error_count > 15)
				phase_reset <= 0;
		end else
*/
		if (hdmi_locked)
		begin
			if (bit_clk)
				error_count <= error_count + 5;
			else
			if (error_count != 0)
				error_count <= error_count - 1;

			if (error_count[20])
			begin
				phase_shift <= phase_shift + 1;
				error_count <= 0;
			end
		end
	end
`endif
/*
	reg [2:0] high_count = 0;
	always @(posedge bit_clk)
	begin
		high_count <= 0;
		phase_reset <= 0;

		if (hdmi_clk_raw)
			high_count <= high_count + 1;

		if (high_count == 3)
			error_count <= error_count + 1;
			phase_reset <= 1;
	end
*/
		
/*
	assign hdmi_clk = hdmi_clk_raw;
*/

//101000000001011111101010000000010111111010
//101000000001011111101010000000010111111010

	lvds_ddr_input lvds0(
		.clk(bit_clk),
		.in_p(d0_p),
		.out(d0_raw)
	);

	lvds_ddr_input lvds1(
		.clk(bit_clk),
		.in_p(d1_p),
		.out(d1_raw)
	);

	lvds_ddr_input lvds2(
		.clk(bit_clk),
		.in_p(d2_p),
		.out(d2_raw)
	);
endmodule

/*
 * built a 8 bit wide register packed into a single ice40 LC.
 */
module ice40_reg8(
	input clk,
	input enable = 1,
	input [7:0] in,
	output [7:0] out
);
	parameter LOCATION = "";

`define DO_SB_LOCATION
`ifdef DO_SB_LOCATION
	(* BEL={LOCATION,"/lc0"} *)
	SB_DFFE buf0( .D(in[0]), .C(clk), .Q(out[0]), .E(enable));

	(* BEL={LOCATION,"/lc1"} *)
	SB_DFFE buf1( .D(in[1]), .C(clk), .Q(out[1]), .E(enable));

	(* BEL={LOCATION,"/lc2"} *)
	SB_DFFE buf2( .D(in[2]), .C(clk), .Q(out[2]), .E(enable));

	(* BEL={LOCATION,"/lc3"} *)
	SB_DFFE buf3( .D(in[3]), .C(clk), .Q(out[3]), .E(enable));

	(* BEL={LOCATION,"/lc4"} *)
	SB_DFFE buf4( .D(in[4]), .C(clk), .Q(out[4]), .E(enable));

	(* BEL={LOCATION,"/lc5"} *)
	SB_DFFE buf5( .D(in[5]), .C(clk), .Q(out[5]), .E(enable));

	(* BEL={LOCATION,"/lc6"} *)
	SB_DFFE buf6( .D(in[6]), .C(clk), .Q(out[6]), .E(enable));

	(* BEL={LOCATION,"/lc7"} *)
	SB_DFFE buf7( .D(in[7]), .C(clk), .Q(out[7]), .E(enable));
`else
	reg [7:0] out;
	always @(posedge clk)
		if (enable)
			out <= in;
`endif
endmodule

/*
 * built a 8 deep shift register packed into a single ice40 LC.
 * out[0] is the newest, out[7] is the oldest.
 */
module ice40_shift8(
	input clk,
	input in,
	input enable = 1,
	output [7:0] out
);
	parameter LOCATION = "";
	wire [7:0] next = { out[6:0], in };

`ifdef DO_SB_LOCATION
	ice40_reg8 #(.LOCATION(LOCATION))
	sr(
		.clk(clk),
		.in(next),
		.out(out),
		.enable(enable)
	);
`else
	reg [7:0] out;
	always @(posedge clk)
		if (enable)
			out <= next;
`endif
endmodule


/*
 * Deserialize 10 input bits into a 10-bit register.
 *
 * Unfortunately this needs some special attention since
 * it is using the DDR input pins (via a 5x PLL), which means
 * that the clock for the in_raw[1] pin is negedge.
 * A three stage shift register is used to try to bring this
 * bit into the posedge domain.
 *
 * To try to ensure that everything can run quickly, the logic
 * cells are hard coded to be close to the input pins.
 *
 * The buffers require two full logic cells (3 buffer, 5 shift)
 * and then one for the output copy.
 * 2 * (4 buffer + 5 shift + 5 copy) + 10
 */
module tmds_shift_register_ddr(
	input reset,
	input hdmi_clk,
	input bit_clk,
	input bit_clk_180,
	input latch_enable,
	input [1:0] in_raw,
	output [BITS-1:0] out,
	output [1:0] out_raw
);
	parameter BITS = 10;
	parameter LOCATION = "";
	parameter LOCATION_0 = "";
	parameter LOCATION_1 = "";
	parameter LOCATION_2 = "";
	parameter LOCATION_3 = "";

	reg [BITS-1:0] out;

`ifdef TMDS_DDR
`define SIMPLE
`ifdef SIMPLE
	reg [BITS-1:0] out;
	reg [7:0] in0, in1;

	// shift the positive and negative edges of the clocks
	ice40_shift8 #(
		.LOCATION(LOCATION_0)
	) shift_0(
		.clk(bit_clk),
		.in(in_raw[0]),
		.out(in0)
	);

	ice40_shift8 #(
		.LOCATION(LOCATION_2)
	) shift_1(
		.clk(~bit_clk),
		.in(in_raw[1]),
		.out(in1)
	);
/*
	always @(posedge bit_clk)
	begin
		in0 <= { in_raw[0], in0[7:1] };
		in1 <= { in_raw[1], in1[7:1] };
	end
*/

	always @(posedge hdmi_clk)
	begin
		//if (hdmi_clk)
			out <= ~{
				in1[3], in0[3],
				in1[4], in0[4],
				in1[5], in0[5],
				in1[6], in0[6],
				in1[7], in0[7]
			};
	end
/*
	reg [15:0] in;
	always @(posedge bit_clk)
	begin
		in <= { in_raw[0], in[15:1] };
		if (hdmi_clk)
			out <= ~in[9:0];
	end
*/
`else
	reg [9:0] out_latch;
	wire [7:0] in0, in1;
	wire [7:0] latch0, latch1;

	//assign out_raw = { in1[0], in0[0] };

	// shift the positive and negative edges of the clocks
	ice40_shift8 #(
		.LOCATION(LOCATION_0)
	) shift_0(
		.clk(bit_clk),
		.in(in_raw[0]),
		.out(in0)
	);

	ice40_shift8 #(
		.LOCATION(LOCATION_2)
	) shift_1(
		.clk(bit_clk),
		.in(in_raw[1]),
		.out(in1)
	);

	// latch the values on the hdmi clock
	// which is only a single clock width of bit_clk
	ice40_reg8 #(
		.LOCATION(LOCATION_1)
	) reg_0(
		.clk(bit_clk),
		.enable(hdmi_clk),
		//.clk(hdmi_clk),
		.in(in0),
		.out(latch0)
	);


	ice40_reg8 #(
		.LOCATION(LOCATION_3)
	) reg_1(
		.clk(bit_clk),
		.enable(hdmi_clk),
		//.clk(hdmi_clk),
		.in(in1),
		.out(latch1)
	);


	reg [7:0] latch1_1, latch1_0;

	always @(posedge hdmi_clk)
	begin
		latch1_1 <= latch1;
		latch1_0 <= latch0;

		out <=
`ifdef BUFFER_LVDS
		~
`endif
		{
			latch1_1[7], latch1_0[7],
			latch1_1[6], latch1_0[6],
			latch1_1[5], latch1_0[5],
			latch1_1[4], latch1_0[4],
			latch1_1[3], latch1_0[3]
		};
	end
`endif
`else
/*
	// not DDR, just a simple shift register
	wire [15:0] in0, latch;
	ice40_shift8 #(
		.LOCATION(LOCATION_0)
	) shift_0(
		.clk(bit_clk),
		.in(in_raw[0]),
		.out(in0[7:0])
	);

	ice40_shift8 #(
		.LOCATION(LOCATION_1)
	) shift_1(
		.clk(bit_clk),
		.in(in0[7]),
		.out(in0[15:8])
	);

	ice40_reg8 #(
		.LOCATION(LOCATION_2)
	) reg_0(
		.clk(bit_clk),
		.enable(hdmi_clk),
		.in(in0[7:0]),
		.out(latch[7:0])
	);
	ice40_reg8 #(
		.LOCATION(LOCATION_3)
	) reg_1(
		.clk(bit_clk),
		.enable(hdmi_clk),
		.in(in0[15:8]),
		.out(latch[15:8])
	);

	always @(posedge hdmi_clk)
	begin
		//in0 <= { in0[8:0], in_raw[0] };
		out <= latch[9:0];
	end
*/
	reg [9:0] in0;
	always @(posedge bit_clk)
	begin
		in0 <= { in0[8:0], in_raw[0] };
		if (hdmi_clk)
			out <= in0;
	end

`endif

endmodule

// detect a control message in the shift register and use it
// to resync our bit clock offset from the pixel clock.
// tracks if our clock is still in sync with the old values
module tmds_sync_recognizer(
	input reset,
	input phase_step,
	input hdmi_clk,
	input [19:0] in,
	output valid,
	output [3:0] phase
);
	//parameter CTRL_00 = 10'b1101010100; // 354
	//parameter CTRL_01 = 10'b0010101011; // 0AB
	//parameter CTRL_10 = 10'b0101010100; // 154
	parameter CTRL_11 = 10'b1010101011; // 2AB
	parameter DELAY_BITS = 22;

	reg valid = 0;
	reg [3:0] phase = 8;
	reg [DELAY_BITS:0] counter;

	// look for CTRL_11 repeated twice to recognize that
	// we are synchronized with the words in the TMDS stream.
	// in order to handle longer possible runs
	reg [9:0] last_in;
	wire [29:0] exp_in = { last_in, in };

	always @(posedge reset or posedge hdmi_clk)
	if (reset)
	begin
		counter <= 0;
		valid <= 0;
		phase <= 0;
	end else begin
		// store just the last half since it will be
		// shifted by ten next time
		last_in <= in[19:10];

		if (exp_in[19+phase:phase] == { CTRL_11, CTRL_11 })
		begin
			// we have a good control word!
			valid <= 1;
			counter <= 0;
		end else
		if (phase_step)
		begin
			if (phase == 4'h9)
				phase <= 0;
			else
				phase <= phase + 1;
		end
		if (counter[DELAY_BITS])
		begin
			valid <= 0;
			counter <= 0;
		end else begin
			// keep counting until we have another valid signal
			counter <= counter + 1;
		end
	end
endmodule


// Synchronize the three channels with the TMDS clock and unknown phase
// of the bits.  Returns the raw 8b10b encoded values for futher processing
// and a TMDS synchronize clock for the data stream.  The data are only valid
// when locked
module tmds_raw_decoder(
	input reset,
	input phase_step,

	input d0_p,
	input d1_p,
	input d2_p,
	input clk_p,
	input [4:0] phase_shift = 0,

	// d0,d1,d2 are phase corrected in clk domain
	output [9:0] d0,
	output [9:0] d1,
	output [9:0] d2,

	// d0_data etc are unphase corrected, but in clk domain
	output [9:0] d0_data,
	output [9:0] d1_data,
	output [9:0] d2_data,

	output valid, // good pixel data
	output locked, // only timing data
	output hdmi_clk,
	output bit_clk,
	output [5:0] out_raw // in hdmi_bit_clk domain, after synchronizers
);
	parameter INVERT = 3'b000;
	wire hdmi_clk; // 25 MHz decoded from TDMS input
	wire bit_clk; // 250 MHz PLL'ed from TMDS clock (or 125 MHz if DDR)
	reg pixel_strobe, pixel_valid; // when new pixels are detected by the synchronizer
	wire hdmi_locked;
	assign locked = hdmi_locked;
	reg valid;

	// in the bit_clk domain, both pos and neg edge
	wire [1:0] in0_raw, in1_raw, in2_raw;

	tmds_ddr_phy phy(
		// inputs
		.reset(reset),
		.d0_p(d0_p),
		.d1_p(d1_p),
		.d2_p(d2_p),
		.clk_p(clk_p),
		.phase_shift(phase_shift),
		// outputs
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.hdmi_locked(hdmi_locked),
		.d0_raw(in0_raw),
		.d1_raw(in1_raw),
		.d2_raw(in2_raw)
	);
	

	// hdmi_clk domain, but not synchronized to the phase
	wire [9:0] d0_data;
	wire [9:0] d1_data;
	wire [9:0] d2_data;

	// 2x shift registers worth of data
	reg [19:0] d0_ext, d1_ext, d2_ext;

	// phase synchronized data (we hope)
	reg [9:0] d0;
	reg [9:0] d1;
	reg [9:0] d2;

	always @(posedge hdmi_clk)
	begin
		d0_ext <= { d0_ext[9:0], INVERT[0] ? ~d0_data : d0_data };
		d1_ext <= { d1_ext[9:0], INVERT[1] ? ~d1_data : d1_data };
		d2_ext <= { d2_ext[9:0], INVERT[2] ? ~d2_data : d2_data };

		d0 <= d0_ext[9+phase:phase];
		d1 <= d1_ext[9+phase:phase];
		d2 <= d2_ext[9+phase:phase];
	end

	// this is a bit of a hack to put the block rams right
	// next to the inputs for the tmds signals.  otherwise
	// the timing gets really bad, depending on the seed etc
	// these also output in the hdmi_clk domain, so no
	// clock crossing is required
/*
	wire [7:0] wr_reg;
	wire next_latch_enable = wr_reg[3:0] == 4'b0000;
	ice40_shift8 #(.LOCATION("X14/Y30"))
	wr_reg_buf(
		.clk(bit_clk),
		.in(next_latch_enable),
		.out(wr_reg)
	);
*/
	reg latch_enable = 0;
	always @(posedge hdmi_clk)
		latch_enable <= ~latch_enable;

	// the latch enable bit will be shifted here after
	// five cycles, so the shift registers will ten new
	// bits of data.  this bit should onlybe high for
	// a single clock cycle
	//wire latch_enable = wr_reg[4];

	// Info: constrained 'tmds_d0n' to bel 'X19/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y25/ram"),
		.LOCATION_0("X21/Y30"),
		.LOCATION_1("X20/Y30"),
		.LOCATION_2("X21/Y29"),
		.LOCATION_3("X20/Y29")
	) d0_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.bit_clk_180(~bit_clk),
		.latch_enable(latch_enable),
		.in_raw(in0_raw),
		.out(d0_data),
		.out_raw(out_raw[1:0])
	);

	// Info: constrained 'tmds_d1n' to bel 'X18/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y29/ram"),
		.LOCATION_0("X18/Y30"),
		.LOCATION_1("X17/Y30"),
		.LOCATION_2("X18/Y29"),
		.LOCATION_3("X17/Y29")
	) d1_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.bit_clk_180(~bit_clk),
		.latch_enable(latch_enable),
		.in_raw(in1_raw),
		.out(d1_data),
		.out_raw(out_raw[3:2])
	);

	// Info: constrained 'tmds_d2p' to bel 'X16/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y27/ram"),
		.LOCATION_0("X16/Y30"),
		.LOCATION_1("X15/Y30"),
		.LOCATION_2("X16/Y29"),
		.LOCATION_3("X15/Y29")
	) d2_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.bit_clk_180(~bit_clk),
		.latch_enable(latch_enable),
		.in_raw(in2_raw),
		.out(d2_data),
		.out_raw(out_raw[5:4])
	);

	// detect the pixel clock from the PLL'ed bit_clk
	// only channel 0 carries the special command words
	// with DDR we only count up to 5 so three bits is enough
	wire [3:0] phase;

	tmds_sync_recognizer d0_sync_recognizer(
		.reset(reset),
		.phase_step(phase_step),
		.hdmi_clk(hdmi_clk),
		.in(d0_ext),
		.phase(phase),
		.valid(pixel_valid)
	);

	always @(posedge hdmi_clk)
	begin
		valid <= hdmi_locked && pixel_valid;
		valid <= pixel_valid;
	end
endmodule

module tmds_decoder(
	input reset,
	input phase_step,

	// the differential pair inputs only take the positive pin
	// otherwise nextpnr gets upset!
	input clk_p,
	input d0_p,
	input d1_p,
	input d2_p,
	input [4:0] phase_shift = 0,

	// hdmi pixel clock and PLL'ed bit clock
	output hdmi_clk,
	output bit_clk,

	// clock sync and data decode is good
	output hdmi_locked, // good clock
	output hdmi_valid, // good sync

	// data valid should be based on sync pulses, so ignore it for now
	output data_valid,
	output [7:0] d0,
	output [7:0] d1,
	output [7:0] d2,

	// hdmi_bit_clk domain. this is only useful for debugging tmds errors
	output [5:0] out_raw,

	// these hold value so sync_valid is not necessary
	output sync_valid,
	output [1:0] sync,

	// terc4 data is not used yet
	output ctrl_valid,
	output [3:0] ctrl
);
	parameter [2:0] INVERT = 3'b000;

	wire [9:0] tmds_d0;
	wire [9:0] tmds_d1;
	wire [9:0] tmds_d2;
	wire hdmi_clk; // hdmi pixel clock domain, sync'ed to the TMDS clock
	wire bit_clk; // PLL'ed from the pixel clock

	wire hdmi_locked; // good clock?
	wire hdmi_valid; // good decode?

	tmds_raw_decoder #(.INVERT(INVERT))
	tmds_raw_i(
		.reset(reset),
		.phase_step(phase_step),

		// physical inputs
		.clk_p(clk_p),
		.d0_p(d0_p),
		.d1_p(d1_p),
		.d2_p(d2_p),
		.phase_shift(phase_shift),

		// outputs
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.locked(hdmi_locked),
		.valid(hdmi_valid),
		.d0(tmds_d0),
		.d1(tmds_d1),
		.d2(tmds_d2),
		.out_raw(out_raw)
	);

	tmds_8b10b_decoder d0_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d0),
		.data(d0),
		.sync(sync),
		.ctrl(ctrl),
		.data_valid(data_valid),
		.sync_valid(sync_valid),
		.ctrl_valid(ctrl_valid),
	);

	// audio data is on d1 and d2, but we don't handle it yet
	tmds_8b10b_decoder d1_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d1),
		.data(d1),
	);

	tmds_8b10b_decoder d2_decoder(
		.hdmi_clk(hdmi_clk),
		.in(tmds_d2),
		.data(d2),
	);
endmodule
