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

module hdmi_pll(
	input  clock_in,
	output clock_out,
	output locked,
	input reset
	);

SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(4'b0000),		// DIVR =  0
		.DIVF(7'b0100111),	// DIVF = 39 for simple
		.DIVQ(3'b011),		// DIVQ =  3
		.FILTER_RANGE(3'b010)	// FILTER_RANGE = 2
	) uut (
		.LOCK(locked),
		.RESETB(~reset),
		.BYPASS(1'b0),
		.REFERENCECLK(clock_in),
		.PLLOUTGLOBAL(clock_out)
		);

endmodule
