module sram
#(parameter DATA_LEN = 32, N_ENTRIES = 1024)
(
    input                           clk,
    input                           en_i,
    input                           we_i,
    input  [$clog2(N_ENTRIES)-1: 0] addr_i,
    input  [DATA_LEN-1: 0]        data_i,
    output reg [DATA_LEN-1: 0]    data_o
);

reg [DATA_LEN-1 : 0] RAM [N_ENTRIES-1: 0];

// ------------------------------------
// Read operation
// ------------------------------------
always@(posedge clk)
begin
    if (en_i)
    begin
        data_o <= RAM[addr_i];
    end
end

// ------------------------------------
// Write operation
// ------------------------------------
always@(posedge clk)
begin
    if (en_i & we_i)
    begin
        RAM[addr_i] <= data_i;
    end
end

endmodule