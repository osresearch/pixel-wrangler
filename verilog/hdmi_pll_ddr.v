/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:  125.000 MHz
 * Achieved output frequency:   125.000 MHz
 */

// things to try for later
//.FEEDBACK_PATH("PHASE_AND_DELAY"),
//.DIVF(7'h4),	// DIVF = 4 for non-simple
//.DELAY_ADJUSTMENT_MODE_FEEDBACK("DYNAMIC"),

//.DYNAMICDELAY(delay)
//.DYNAMICDELAY(7'h11)
//input [7:0] delay

// 125 MHz == 8 ns/clock
// 16 * 150ps per delay == 2.4 ns
// maximum phase delay is 1/4 clock
// guessing at a value seems to work well?

module hdmi_pll(
	input  clock_in,
	output clock_out,
	output locked,
	input reset,
	input [7:0] delay
	);

	// these move the PLL rising edge relative to the
	// input clock's rising edge. each step is around 150ps
	parameter ADVANCE = 4'd0;
	parameter DELAY = 4'd0;

// based on the https://github.com/YosysHQ/icestorm/wiki/iCE40-PLL-documentation
// out = in * 4 * (divf + 1) / (divr + 1) / 2^divq
// we want 5x the input clock, so DIVF = 5 - 1
// the shit register has a 4x multiplier effect on DIVF,
// this produces a 20x clock, so we divide by 4 (DIVR=4-1)
// divq does not seem to matter as long as it is non-zero?
SB_PLL40_CORE #(
		.FEEDBACK_PATH("PHASE_AND_DELAY"),
		.DIVR(4'd0),		// DIVR =  4 - 1
		.DIVF(7'd4),	// DIVF = 5 - 1
		.DIVQ(3'b001),		// DIVQ =  3
		.FILTER_RANGE(3'b010),	// FILTER_RANGE = 2
		.FDA_FEEDBACK(ADVANCE),
		.FDA_RELATIVE(DELAY),
		.DELAY_ADJUSTMENT_MODE_FEEDBACK("DYNAMIC"),
		.DELAY_ADJUSTMENT_MODE_RELATIVE("DYNAMIC"),
		.PLLOUT_SELECT("SHIFTREG_90deg")
	) uut (
		.LOCK(locked),
		.RESETB(~reset),
		.BYPASS(1'b0),
		.DYNAMICDELAY(delay),
		.REFERENCECLK(clock_in),
		.PLLOUTGLOBAL(clock_out)
		);

endmodule
