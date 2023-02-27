`ifndef _util_v_
`define _util_v_

module tristate(
	inout pin,
	input enable,
	input data_out,
	output data_in
);
	SB_IO #(
		.PIN_TYPE(6'b1010_01) // tristatable output
	) buffer(
		.PACKAGE_PIN(pin),
		.OUTPUT_ENABLE(enable),
		.D_IN_0(data_in),
		.D_OUT_0(data_out)
	);
endmodule

`endif
