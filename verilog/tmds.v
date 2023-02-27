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


// Deserialize 10 input bits into a 10-bit register,
// clocking on the rising edge of the bit clock using a DDR pin
// to capture two bits per clock (the PLL clock runs at 5x the TMDS clock)
// the bits are sent LSB first
module tmds_shift_register_ddr(
	input bit_clk,
	input in_p,
	output [BITS-1:0] out
);
	parameter INVERT = 0;
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

	reg in1_0;
	reg in0_0;

	// if we copy the negedge bit we spend less routing time?
	always @(negedge bit_clk)
		in1_0 <= INVERT ? ~in1 : in1;

	always @(posedge bit_clk)
	begin
		in0_0 <= INVERT ? ~in0 : in0;
		out <= { in1_0, in0_0, out[BITS-1:2] };
	end
endmodule

// non ddr version for a 10 bit shift register
module tmds_shift_register(
	input bit_clk,
	input in_p,
	output [BITS-1:0] out
);
	parameter INVERT = 0;
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
		out <= { INVERT ? ~in0 : in0, out[BITS-1:1] };
endmodule

// detect a control message in the shift register and use it
// to resync our bit clock offset from the pixel clock.
// tracks if our clock is still in sync with the old values
module tmds_sync_recognizer(
	input reset,
	input hdmi_clk,
	input [9:0] in,
	output valid,
	output [2:0] phase
);
	//parameter CTRL_00 = 10'b1101010100; // 354
	//parameter CTRL_01 = 10'b0010101011; // 0AB
	//parameter CTRL_10 = 10'b0101010100; // 154
	parameter CTRL_11 = 10'b1010101011; // 2AB
	parameter DELAY_BITS = 24;

	reg valid = 0;
	reg [2:0] phase = 0;
	reg [DELAY_BITS:0] counter;

	always @(posedge reset or posedge hdmi_clk)
	begin
		if (reset)
		begin
			counter <= 0;
			valid <= 0;
		end else
		if (in == CTRL_11)
		begin
			// we have a good control word!
			valid <= 1;
			counter <= 0;
		end else
		if (counter[DELAY_BITS])
		begin
			// no recent control word! adjust the phase
			if (phase == 4'h4)
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


module tmds_clock_cross(
	input reset,
	input clk,
	input bit_clk,
	input [2:0] phase,
	input [9:0] d0_data,
	input [9:0] d1_data,
	input [9:0] d2_data,
	output [9:0] d0,
	output [9:0] d1,
	output [9:0] d2
);
	reg wen;
	reg [2:0] bit_counter = 0;
	reg [9:0] d0;
	reg [9:0] d1;
	reg [9:0] d2;
	wire [9:0] d0_rd;
	wire [9:0] d1_rd;
	wire [9:0] d2_rd;

	always @(posedge reset or posedge bit_clk)
	if (reset)
	begin
		bit_counter <= 0;
		wen <= 0;
	end else begin
		wen <= bit_counter == phase;

		if (bit_counter == 4'h4)
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
		.wr_addr(1'b0),
		.wr_data({d0_data, d1_data, d2_data}),
		.rd_clk(clk),
		.rd_addr(1'b0),
		.rd_data({d0_rd,d1_rd,d2_rd})
	);

	always @(posedge clk)
	begin
		d0 <= d0_rd;
		d1 <= d1_rd;
		d2 <= d2_rd;
	end
endmodule


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
	output bit_clk
);
	parameter [2:0] INVERT = 3'b000;
	wire hdmi_clk; // 25 MHz decoded from TDMS input
	wire bit_clk; // 250 MHz PLL'ed from TMDS clock (or 125 MHz if DDR)
	reg pixel_strobe, pixel_valid; // when new pixels are detected by the synchronizer
	wire hdmi_locked;
	assign locked = hdmi_locked;
	reg valid;

	tmds_clk_pll tmds_clk_pll_i(
		.reset(reset),
		.clk_p(clk_p),
		.hdmi_clk(hdmi_clk),
		.bit_clk(bit_clk),
		.locked(hdmi_locked)
	);

	// bit_clk domain
	wire [9:0] d0_data;
	wire [9:0] d1_data;
	wire [9:0] d2_data;

	tmds_shift_register_ddr #(.INVERT(INVERT[0])) d0_shift(
		.bit_clk(bit_clk),
		.in_p(d0_p),
		.out(d0_data)
	);

	tmds_shift_register #(.INVERT(INVERT[1])) d1_shift(
		.bit_clk(bit_clk),
		.in_p(d1_p),
		.out(d1_data)
	);

	tmds_shift_register #(.INVERT(INVERT[2])) d2_shift(
		.bit_clk(bit_clk),
		.in_p(d2_p),
		.out(d2_data)
	);

	// detect the pixel clock from the PLL'ed bit_clk
	// only channel 0 carries the special command words
	// with DDR we only count up to 5 so three bits is enough
	wire [2:0] phase;

	tmds_sync_recognizer d0_sync_recognizer(
		.reset(reset),
		.hdmi_clk(hdmi_clk),
		.in(d0),
		.phase(phase),
		.valid(pixel_valid)
	);

	// cross the data words from bit_clk to clk domain
	tmds_clock_cross crosser(
		.reset(reset),
		.clk(hdmi_clk),
		.bit_clk(bit_clk),
		.phase(phase),
		.d0_data(d0_data),
		.d1_data(d1_data),
		.d2_data(d2_data),
		.d0(d0),
		.d1(d1),
		.d2(d2)
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
