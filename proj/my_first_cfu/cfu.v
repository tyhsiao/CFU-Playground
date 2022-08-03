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
localparam INPUT_DATA_SIZE = 18435;

// Dismantle Function Code
wire [6:0] func7;
wire [2:0] func3;

assign func7 = cmd_payload_function_id[9:3];
assign func3 = cmd_payload_function_id[2:0];



//*****      Control Siganl       *****//


always @(posedge clk) begin
  if (reset) rsp_valid <= 1'b0;
  // Waiting to hand off response to CPU.
  else if (rsp_valid) rsp_valid <= ~rsp_ready;
  else if (acc_start_delay && ~acc_start) rsp_valid <= 1;
  else if (cmd_valid) begin
    if(func7 != 7'd10) rsp_valid <= 1;  
    else rsp_valid <= rsp_valid;
  end 
end

// Only not ready for a command when we have a response or not running for acc.
assign cmd_ready = ( ~rsp_valid && ~acc_start && ~cal_finish) ;


//***** Set Conv Parameters *****//
reg signed [31:0] input_offset, input_height, input_width, input_batches, input_depth;
reg signed [31:0] filter_input_depth, filter_height, filter_width, filter_output_depth;
reg signed [31:0] dilation_width_factor, dilation_height_factor;

reg [6:0] param_index;

always @(posedge clk) begin
  if(reset || (cmd_valid && func7 == 7'd6)) begin
    input_offset <= 0;
    input_height <= 0;
    input_width <= 0;
    input_batches <= 0;
    input_depth <= 0;
    filter_input_depth <= 0;
    filter_height <= 0;
    filter_width <= 0;
    filter_output_depth <= 0;
    param_index <= 0;
  end

  else if (cmd_valid && func7 == 7'd7) begin

    case(param_index)
      7'd0: begin
        input_offset    <= cmd_payload_inputs_0;
        param_index     <= param_index + 1;
      end

      7'd1: begin
        input_batches   <= cmd_payload_inputs_0;
        input_height    <= cmd_payload_inputs_1;
        param_index     <= param_index + 1;
      end

      7'd2: begin
        input_width     <= cmd_payload_inputs_0;
        input_depth     <= cmd_payload_inputs_1;
        param_index     <= param_index + 1;
      end

      7'd3: begin
        filter_output_depth   <= cmd_payload_inputs_0;
        filter_height         <= cmd_payload_inputs_1;
        param_index           <= param_index + 1;
      end

      7'd4: begin
        filter_width          <= cmd_payload_inputs_0;
        filter_input_depth    <= cmd_payload_inputs_1;
        param_index           <= param_index + 1;
      end

      7'd5: begin
        dilation_width_factor   <= cmd_payload_inputs_0;
        dilation_height_factor  <= cmd_payload_inputs_1;
        param_index             <= param_index + 1;
      end      

      default: param_index <= param_index;
    endcase 
  end
end

reg signed [31:0] in_x_origin, in_y_origin, batch, out_channel, group;
reg [4:0] param2_index;

always @(posedge clk) begin
  if(reset || (func7 == 7'd8 && cmd_valid)) begin
    in_x_origin <= 0;
    in_y_origin <= 0;
    batch <= 0;
    out_channel <= 0;
    group <= 0;
    param2_index <= 0;
  end

  else if(cmd_valid && func7 == 7'd9) begin
    case(param2_index)
    5'd0: begin
      in_x_origin <= cmd_payload_inputs_0;
      in_y_origin <= cmd_payload_inputs_1;
      param2_index <= param2_index + 1;
    end

    5'd1: begin
      batch <= cmd_payload_inputs_0;
      out_channel <= cmd_payload_inputs_1;
      param2_index <= param2_index + 1;
    end

    5'd2: begin
      group <= cmd_payload_inputs_0;
      param2_index <= param2_index + 1;
    end

    default: param2_index <= param2_index;
    endcase
  end
end

//***** Conv ACC Data Calculation *****//

wire signed [31:0] in_x, in_y;
reg [31:0] filter_x, filter_y, in_channel;
wire is_point_inside_image;
reg  acc_start, acc_start_delay;
reg  cal_now, cal_now_delay;
reg  cal_finish;
wire cond1 , cond2;

assign cond1 =  acc_start && (filter_y == filter_height - 1) && (filter_x == filter_width - 1) && ~is_point_inside_image;
assign cond2 = acc_start && (filter_y == filter_height - 1) && (filter_x == filter_width - 1) && !cal_now && cal_now_delay ;

always @(posedge clk) begin
  if(reset | rsp_valid) cal_finish <= 0;
  else if ( cond1 | cond2 )cal_finish <= 1;
  else cal_finish <= cal_finish;
end

always @(posedge clk )begin
  acc_start_delay <= acc_start;
  cal_now_delay <= cal_now;
end

assign in_x = in_x_origin + (dilation_width_factor * filter_x);
assign in_y = in_y_origin + (dilation_height_factor * filter_y);
assign is_point_inside_image =
        (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
        (in_y < input_height);

always @(posedge clk) begin
  if( reset ) acc_start <= 0;
  else if ( cond1 | cond2 | cal_finish)acc_start <= 0;
  else if (cmd_valid && func7 == 7'd10) acc_start <= 1;
  else acc_start <= acc_start;
end

// filter X
always @(posedge clk) begin
  if(reset) filter_x <= 0;
  else if (cmd_valid && func7 == 7'd8) filter_x <= 0;
  else if(acc_start) begin
    if (cal_now) filter_x <= filter_x;
    else if(filter_x == filter_width - 1) begin
      if (filter_y == filter_height - 1 ) filter_x <= filter_x;
      else filter_x <= 0;
    end 
    else filter_x <= filter_x + 1;
  end
  else filter_x <= filter_x;
end

// filter Y
always @(posedge clk) begin
  if(reset) filter_y <= 0;
  else if (cmd_valid && func7 == 7'd8) filter_y <= 0;
    
  else if(acc_start) begin
    if (cal_now) filter_y <= filter_y;
    else if ( filter_y == filter_height - 1 ) filter_y <= filter_y;
    else if ( filter_x == filter_width - 1) filter_y <= filter_y + 1; 
    else filter_y <= filter_y;
  end

  else filter_y <= filter_y;
end

// control signal to calculate

always @(posedge clk) begin
  if (reset) cal_now <= 0;
  else if(cond1 | cond2) cal_now <= 0;
  else if(in_channel == filter_input_depth - 1) cal_now <= 0;
  else if(acc_start && is_point_inside_image) cal_now <= 1; 
  // wait for complete
  else cal_now <= cal_now;
end

// in_channel
always @(posedge clk) begin
  if(reset) in_channel <= 0;
  else if(cmd_valid && func7 == 7'd8) in_channel <= 0;
  else if(in_channel == filter_input_depth - 1) in_channel <= 0;
  else if(acc_start && cal_now) in_channel <= in_channel + 1;
  else in_channel <= in_channel;

end

// Main Acc
//index method ((i0 * dims_data[1] + i1) * dims_data[2] + i2) * dims_data[3] + i3;
wire [31:0] input_index, filter_index; 

assign input_index = 
  ((((batch * input_height + in_y) * input_width ) + in_x) * input_depth ) + (in_channel + group * filter_input_depth);

assign filter_index = 
  ((((out_channel * filter_height + filter_y) * filter_width ) + filter_x) * filter_input_depth ) + (in_channel);


always @(posedge clk) begin
  if(reset) rsp_payload_outputs_0 <= 32'b0;
  else if( cmd_valid && func7 == 7'd8 ) rsp_payload_outputs_0 <= 32'b0;
  else if (cal_now) rsp_payload_outputs_0 <= rsp_payload_outputs_0 + prod_0;
end

// SIMD multiply step:
wire signed [31:0] prod_0;
assign prod_0 =  (($signed(input_data[input_index]) + $signed(input_offset))
                 * $signed(filter_data[filter_index]));



//*****     Get Filter Data     *****//

reg signed [7:0] filter_data [0:FILTER_DATA_SIZE];
reg [31:0] cfilt;

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

//*****     Get Input Data     *****//

reg signed [7:0] input_data [0:INPUT_DATA_SIZE];
reg [31:0] ifilt;

always @(posedge clk) begin
  if (reset) begin 
    input_data <= '{default: '0}; 
    ifilt <= 0;
  end

  else if (cmd_valid) begin
    if (func7 == 7'd3) begin
      input_data <= '{default: '0}; 
      ifilt <= 0;
    end

    else if (func7 == 7'd4) begin
      // Change the order of memory due to little endian system
      input_data[ifilt  ] <= $signed(cmd_payload_inputs_0[ 7: 0]);
      input_data[ifilt+1] <= $signed(cmd_payload_inputs_0[15: 8]);
      input_data[ifilt+2] <= $signed(cmd_payload_inputs_0[23:16]);
      input_data[ifilt+3] <= $signed(cmd_payload_inputs_0[31:24]);
      input_data[ifilt+4] <= $signed(cmd_payload_inputs_1[ 7: 0]);
      input_data[ifilt+5] <= $signed(cmd_payload_inputs_1[15: 8]);
      input_data[ifilt+6] <= $signed(cmd_payload_inputs_1[23:16]);
      input_data[ifilt+7] <= $signed(cmd_payload_inputs_1[31:24]);
      ifilt <= ifilt + 6'd8;
    end

    else if (func7 == 7'd5) begin
      input_data[ifilt] <= $signed(cmd_payload_inputs_0[31:24]);
      ifilt <= ifilt + 1;
    end
  end
 
end



endmodule