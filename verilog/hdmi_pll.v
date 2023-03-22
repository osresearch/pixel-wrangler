/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:  250.000 MHz
 * Achieved output frequency:   250.000 MHz
 */

module hdmi_pll(
	input reset,
	input  clock_in,
	output clock_out,
	output locked,
	input [3:0] delay
	);

	parameter DELAY = 4'b0000;

SB_PLL40_CORE #(
		.FEEDBACK_PATH("PHASE_AND_DELAY"),
		.DIVR(4'd3),		// DIVR =  0
		.DIVF(7'h9),	// DIVF = 39 for simple, 9 for non
		.DIVQ(3'd4),		// DIVQ =  2
		.FILTER_RANGE(3'b010),	// FILTER_RANGE = 2
		//.DELAY_ADJUSTMENT_MODE_FEEDBACK("DYNAMIC")
		//.DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
		//.FDA_RELATIVE(DELAY),
		//.PLLOUT_SELECT("SHIFTREG_0deg")
	) uut (
		.LOCK(locked),
		.RESETB(~reset),
		.BYPASS(1'b0),
		.REFERENCECLK(clock_in),
		.PLLOUTGLOBAL(clock_out),
		//.DYNAMICDELAY({4'b0000, delay})
		//.DYNAMICDELAY({delay, 4'b0000})
		);

endmodule
