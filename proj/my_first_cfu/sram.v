module sram
#(parameter DATA_LEN = 8, N_ENTRIES = 10240)
(
    input                           clk,
    input                           en_i,
    input                           reset,
    input  [7:0]                    we_i,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i0,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i1,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i2,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i3,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i4,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i5,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i6,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i7,

    input  [DATA_LEN-1: 0]        data_i0,
    input  [DATA_LEN-1: 0]        data_i1,
    input  [DATA_LEN-1: 0]        data_i2,
    input  [DATA_LEN-1: 0]        data_i3,
    input  [DATA_LEN-1: 0]        data_i4,
    input  [DATA_LEN-1: 0]        data_i5,
    input  [DATA_LEN-1: 0]        data_i6,
    input  [DATA_LEN-1: 0]        data_i7,
    output reg [DATA_LEN-1: 0]    data_o
);

reg [DATA_LEN-1 : 0] RAM [N_ENTRIES-1: 0];

// ------------------------------------
// Read operation
// ------------------------------------
always@(posedge clk) begin
    if (en_i) begin
        data_o <= RAM[addr_i0];
    end
end

// ------------------------------------
// Write operation
// ------------------------------------
always@(posedge clk or posedge reset) begin
    if (reset)  RAM <= '{default: '0}; 

    else begin
        if (en_i & we_i[7]) RAM[addr_i7] <= data_i7;
        if (en_i & we_i[6]) RAM[addr_i6] <= data_i6;
        if (en_i & we_i[5]) RAM[addr_i5] <= data_i5;
        if (en_i & we_i[4]) RAM[addr_i4] <= data_i4;
        if (en_i & we_i[3]) RAM[addr_i3] <= data_i3;
        if (en_i & we_i[2]) RAM[addr_i2] <= data_i2;
        if (en_i & we_i[1]) RAM[addr_i1] <= data_i1;
        if (en_i & we_i[0]) RAM[addr_i0] <= data_i0;
    end
end


endmodule