module Cfu (
  input               cmd_valid,
  output              cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output reg          rsp_valid,
  input               rsp_ready,
  output reg [31:0]   rsp_payload_outputs_0,
  input               reset,
  input               clk
);

localparam FILTER_DATA_SIZE = 65536;

// Dismantle Function Code
wire [6:0] func7;
wire [2:0] func3;

assign func7 = cmd_payload_function_id[9:3];
assign func3 = cmd_payload_function_id[2:0];


//***** Set Conv Parameters *****//
reg signed [31:0] input_offset;

always @(posedge clk) begin
  if(reset) input_offset <= 32'b0;
  else if(cmd_valid) begin
    if (func7 == 7'd5) input_offset <= cmd_payload_inputs_0;
  end
end

//***** Conv ACC Data Calculation *****//

// SIMD multiply step:
wire signed [31:0] prod_0;
assign prod_0 =  (($signed(cmd_payload_inputs_0) + $signed(input_offset))
                 * $signed(filter_data[cmd_payload_inputs_1]));

always @(posedge clk) begin
  if(reset) rsp_payload_outputs_0 <= 32'b0;
  else if(cmd_valid)  begin
    if (func7 == 7'd4) rsp_payload_outputs_0 <= 32'b0;
      else if (func7 == 7'd3) rsp_payload_outputs_0 <= rsp_payload_outputs_0 + prod_0;
    // else if (func7 == 7'd3) rsp_payload_outputs_0 <= cmd_payload_inputs_0;
    // else if (func7 == 7'd3) begin
    //   $display("[cfu.v] Input Value: %d, Filter Value: %d, Input Offset: %d\n", $signed(cmd_payload_inputs_0) , $signed(filter_data[cmd_payload_inputs_1]) , input_offset);
    //   $display("[cfu.v] ACC: %d\n", prod_0);
    // end

  end 

end


//*****      Control Siganl       *****//


always @(posedge clk) begin
  if (reset) rsp_valid <= 1'b0;
  // Waiting to hand off response to CPU.
  else if (rsp_valid) rsp_valid <= ~rsp_ready;
  else if (cmd_valid) rsp_valid <= 1'b1;
end

// Only not ready for a command when we have a response.
assign cmd_ready = ~rsp_valid;

//*****     Get Filter Data     *****//

reg signed [7:0] filter_data [0:FILTER_DATA_SIZE];
reg [31:0] cfilt;
integer idx;

always @(posedge clk) begin
  if (reset) begin 
    filter_data <= '{default: '0}; 
    cfilt <= 0;
  end

  else if (cmd_valid) begin
    if (func7 == 0) begin
      filter_data <= '{default: '0}; 
      cfilt <= 0;
    end

    else if (func7 == 1) begin
      // Change the order of memory due to little endian system
      filter_data[cfilt  ] <= $signed(cmd_payload_inputs_0[ 7: 0]);
      filter_data[cfilt+1] <= $signed(cmd_payload_inputs_0[15: 8]);
      filter_data[cfilt+2] <= $signed(cmd_payload_inputs_0[23:16]);
      filter_data[cfilt+3] <= $signed(cmd_payload_inputs_0[31:24]);
      filter_data[cfilt+4] <= $signed(cmd_payload_inputs_1[ 7: 0]);
      filter_data[cfilt+5] <= $signed(cmd_payload_inputs_1[15: 8]);
      filter_data[cfilt+6] <= $signed(cmd_payload_inputs_1[23:16]);
      filter_data[cfilt+7] <= $signed(cmd_payload_inputs_1[31:24]);
      cfilt <= cfilt + 6'd8;
    end

    else if (func7 == 7'd2) begin
      filter_data[cfilt] <= $signed(cmd_payload_inputs_0[31:24]);
      cfilt <= cfilt + 1;
    end
  end
 
end

endmodule