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
`include "hdmi_pll_ddr.v"
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
	wire [1:0] out;
	reg [1:0] in;

	SB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) diff_io (
		.PACKAGE_PIN(in_p),
		.INPUT_CLK(clk),
		.D_IN_0(out[0]), // pos edge of bit_clk
		.D_IN_1(out[1])  // neg edge of bit_clk
	);

/*
	// invert both of them so that there is a constant delay
	// between the inputs and the latches. also seems to
	// produce a better timing result, so leave it in?
	always @(posedge clk)
		out[0] <= ~in[0];
	always @(negedge clk)
		out[1] <= ~in[1];
*/
endmodule


/*
 * Setup a 5X PLL for the hdmi clock that feeds into a global buffer
 */
module tmds_clk_pll(
	input reset,
	input clk_p,
	output hdmi_clk,
	output bit_clk,
	output locked
);
	SB_GB_IO #(
		.PIN_TYPE(6'b000000),
		.IO_STANDARD("SB_LVDS_INPUT")
	) differential_clock_input (
		.PACKAGE_PIN(clk_p),
		.GLOBAL_BUFFER_OUTPUT(hdmi_clk)
	);

	hdmi_pll pll(
		.clock_in(hdmi_clk),
		.clock_out(bit_clk),
		.locked(locked),
		.reset(reset)
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
	output bit_clk,
	output hdmi_clk,
	output hdmi_locked,
	output [1:0] d0_raw,
	output [1:0] d1_raw,
	output [1:0] d2_raw
);
	tmds_clk_pll tmds_clk_pll_i(
		.reset(reset),
		.clk_p(clk_p),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.locked(hdmi_locked)
	);

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
 * Deserialize 10 input bits into a 10-bit register.
 *
 * This uses a LVDS DDR input to capture two bits per clock,
 * using a 5x PLL off the HDMI clock.  To transfer them to
 * the HDMI clock domain, it uses a dual port block ram
 * configured with a 2-bit write port and 16-bit read port.
 * This allows individual bits to be written, and then
 * an entire 10-bit tmds word to be read.
 *
 * To avoid overwriting the one that the HDMI clock domain
 * is reading, it alternates between address 0 and 1 in
 * the 16-bit address space.
 *
 * TODO: move write address stuff to outside
 */
module tmds_shift_register_ddr(
	input reset,
	input hdmi_clk,
	input bit_clk,
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
	parameter LOCATION_4 = "";
	parameter LOCATION_5 = "";
	parameter LOCATION_6 = "";
	parameter LOCATION_7 = "";

`undef USE_BLOCKRAM
`ifdef USE_BLOCKRAM
	wire in0, in1;
	wire in0_0, in1_0;
	wire in0_1, in1_1;

	// place two shift registers next to the input pins
	(* BEL=LOCATION_0 *)
	SB_DFF buf1_0(
		.D(in_raw[1]),
		.C(bit_clk),
		.Q(in1_0)
	);
	(* BEL=LOCATION_1 *)
	SB_DFF buf1_1(
		.D(in1_0),
		.C(bit_clk),
		.Q(in1_1)
	);
	(* BEL=LOCATION_2 *)
	SB_DFF buf1_2(
		.D(in1_1),
		.C(bit_clk),
		.Q(in1)
	);

	(* BEL=LOCATION_3 *)
	SB_DFF buf0_0(
		.D(in_raw[0]),
		.C(bit_clk),
		.Q(in0_0)
	);
	(* BEL=LOCATION_4 *)
	SB_DFF buf0_1(
		.D(in0_0),
		.C(bit_clk),
		.Q(in0_1)
	);
	(* BEL=LOCATION_5 *)
	SB_DFF buf0_2(
		.D(in0_1),
		.C(bit_clk),
		.Q(in0)
	);

	wire [15:0] rd_data0, rd_data1;
	reg [BITS-1:0] out;

	// extract just the low-order bits from the 16
	//assign out = rd_data[9:0];

	reg [2:0] wr_bits0 = 0, wr_bits1 = 0;
	reg [1:0] wr_addr0 = 0, wr_addr1 = 0;
	reg [1:0] rd_addr = 0;

	always @(posedge reset or posedge bit_clk)
	begin
		wr_bits0 <= wr_bits0 + 1;
		if (reset)
		begin
			wr_bits0 <= 0;
			wr_addr0 <= 0;
		end else
		if (wr_bits0 == 3'h4)
		begin
			wr_bits0 <= 0;
			wr_addr0 <= wr_addr0 + 1;
		end
	end

	always @(posedge hdmi_clk)
	if (reset)
		rd_addr <= 1;
	else begin
		rd_addr <= rd_addr + 1;

		out <= rd_data0[9:0];
	end

	dpram_2x16 #(
		.LOCATION(LOCATION)
	) dpram_buf0(
		.wr_clk(bit_clk),
		.wr_addr({6'b0, wr_addr0, wr_bits0}),
		.wr_data({in1, in0}),
		.wr_enable(1'b1),
		.rd_clk(hdmi_clk),
		.rd_data(rd_data0),
		.rd_addr({6'h00, rd_addr})
	);
`else
	// simple shift registers that clock out every five clocks
	reg [3:0] wr_bits0 = 0, wr_bits1 = 0;
	reg [4:0] shift0, shift1;
	reg [9:0] latch0, latch1, latch2;
	wire in0, in1;
	wire in0_0, in1_0;
	wire in0_1, in1_1;
	wire in0_2, in1_2;

	// place two shift registers next to the input pins
	(* BEL=LOCATION_0 *)
	SB_DFF buf1_0(
		.D(in_raw[1]),
		.C(bit_clk),
		.Q(in1_0)
	);
	(* BEL=LOCATION_1 *)
	SB_DFF buf1_1(
		.D(in1_0),
		.C(bit_clk),
		.Q(in1_1)
	);
	(* BEL=LOCATION_2 *)
	SB_DFF buf1_2(
		.D(in1_1),
		.C(bit_clk),
		.Q(in1_2)
	);
	(* BEL=LOCATION_3 *)
	SB_DFF buf1_3(
		.D(in1_2),
		.C(bit_clk),
		.Q(in1)
	);

	(* BEL=LOCATION_4 *)
	SB_DFF buf0_0(
		.D(in_raw[0]),
		.C(bit_clk),
		.Q(in0_0)
	);
	(* BEL=LOCATION_5 *)
	SB_DFF buf0_1(
		.D(in0_0),
		.C(bit_clk),
		.Q(in0_1)
	);
	(* BEL=LOCATION_6 *)
	SB_DFF buf0_2(
		.D(in0_1),
		.C(bit_clk),
		.Q(in0_2)
	);
	(* BEL=LOCATION_7 *)
	SB_DFF buf0_3(
		.D(in0_2),
		.C(bit_clk),
		.Q(in0)
	);

	reg [1:0] out_raw;

	always @(posedge bit_clk)
	begin
		wr_bits0 <= wr_bits0 + 1;
		shift0 <= { in0, shift0[4:1] };
		shift1 <= { in1, shift1[4:1] };

		out_raw <= { in1, in0 };

		if (wr_bits0 == 3'h4)
		begin
			wr_bits0 <= 0;
			latch0 <= shift0;
			latch1 <= shift1;
		end
	end

	reg [BITS-1:0] out;
	always @(posedge hdmi_clk)
	begin
		out <= latch2;
		//latch2 <= latch1;
		//latch1 <= latch0;
		latch2 <= {
			latch1[4], latch0[4],
			latch1[3], latch0[3],
			latch1[2], latch0[2],
			latch1[1], latch0[1],
			latch1[0], latch0[0]
		};
	end
`endif
endmodule

// detect a control message in the shift register and use it
// to resync our bit clock offset from the pixel clock.
// tracks if our clock is still in sync with the old values
module tmds_sync_recognizer(
	input reset,
	input hdmi_clk,
	input [19:0] in,
	output valid,
	output [3:0] phase
);
	//parameter CTRL_00 = 10'b1101010100; // 354
	//parameter CTRL_01 = 10'b0010101011; // 0AB
	//parameter CTRL_10 = 10'b0101010100; // 154
	parameter CTRL_11 = 10'b1010101011; // 2AB
	parameter DELAY_BITS = 21;

	reg valid = 0;
	reg [3:0] phase = 0;
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
		if (counter[DELAY_BITS])
		begin
			// no recent control word! adjust the phase
			if (phase == 4'h9)
				phase <= 0;
			else
				phase <= phase + 1;

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

	input d0_p,
	input d1_p,
	input d2_p,
	input clk_p,

	// d0,d1,d2 are in clk domain
	output [9:0] d0,
	output [9:0] d1,
	output [9:0] d2,
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

	// Info: constrained 'tmds_d0n' to bel 'X19/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y25/ram"),
		.LOCATION_0("X20/Y30/lc7"),
		.LOCATION_1("X20/Y30/lc6"),
		.LOCATION_2("X20/Y30/lc5"),
		.LOCATION_3("X20/Y30/lc4"),
		.LOCATION_4("X20/Y30/lc3"),
		.LOCATION_5("X20/Y30/lc2"),
		.LOCATION_6("X20/Y30/lc1"),
		.LOCATION_7("X20/Y30/lc0")
	) d0_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.in_raw(in0_raw),
		.out(d0_data),
		.out_raw(out_raw[1:0])
	);

	// Info: constrained 'tmds_d1n' to bel 'X18/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y29/ram"),
		.LOCATION_0("X18/Y30/lc7"),
		.LOCATION_1("X18/Y30/lc6"),
		.LOCATION_2("X18/Y30/lc5"),
		.LOCATION_3("X18/Y30/lc4"),
		.LOCATION_4("X18/Y30/lc3"),
		.LOCATION_5("X18/Y30/lc2"),
		.LOCATION_6("X18/Y30/lc1"),
		.LOCATION_7("X18/Y30/lc0")
	) d1_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.in_raw(in1_raw),
		.out(d1_data),
		.out_raw(out_raw[3:2])
	);

	// Info: constrained 'tmds_d2p' to bel 'X16/Y31/io0'
	tmds_shift_register_ddr #(
		.LOCATION("X19/Y27/ram"),
		.LOCATION_0("X16/Y30/lc7"),
		.LOCATION_1("X16/Y30/lc6"),
		.LOCATION_2("X16/Y30/lc5"),
		.LOCATION_3("X16/Y30/lc4"),
		.LOCATION_4("X16/Y30/lc3"),
		.LOCATION_5("X16/Y30/lc2"),
		.LOCATION_6("X16/Y30/lc1"),
		.LOCATION_7("X16/Y30/lc0")
	) d2_shift(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
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

	// the differential pair inputs only take the positive pin
	// otherwise nextpnr gets upset!
	input clk_p,
	input d0_p,
	input d1_p,
	input d2_p,

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

		// physical inputs
		.clk_p(clk_p),
		.d0_p(d0_p),
		.d1_p(d1_p),
		.d2_p(d2_p),

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
