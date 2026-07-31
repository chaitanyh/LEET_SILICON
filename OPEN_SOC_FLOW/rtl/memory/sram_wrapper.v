// =============================================================================
// SRAM Wrapper — Wishbone-compatible 32-bit SRAM interface
// Targets sky130_sram_1kbyte_1rw1r_32x256_8 macro (256 words × 32-bit)
// =============================================================================
`default_nettype none

module sram_wrapper #(
    parameter ADDR_BITS = 8,    // 256 locations
    parameter DATA_BITS = 32
)(
    input                    clk,
    input                    rst_n,

    // Wishbone slave port
    input                    wb_cyc,
    input                    wb_stb,
    input                    wb_we,
    input  [ADDR_BITS+1:0]   wb_addr,   // byte-addressed, lower 2 bits ignored
    input  [DATA_BITS-1:0]   wb_wdata,
    input  [DATA_BITS/8-1:0] wb_sel,
    output [DATA_BITS-1:0]   wb_rdata,
    output                   wb_ack
);
    // ── Word address ─────────────────────────────────────────────────────────
    wire [ADDR_BITS-1:0] waddr = wb_addr[ADDR_BITS+1:2];

    // ── Single-cycle ACK ─────────────────────────────────────────────────────
    reg ack_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ack_r <= 1'b0;
        else        ack_r <= wb_cyc & wb_stb & ~ack_r;
    end
    assign wb_ack = ack_r;

    // ── Byte-enabled SRAM model (behavioral — replaced by macro in P&R) ──────
    // In synthesis this infers BRAM/registers; OpenRAM macro replaces this block.
    reg [DATA_BITS-1:0] mem [0:(1<<ADDR_BITS)-1];

    // Write with byte enables
    integer k;
    always @(posedge clk) begin
        if (wb_cyc & wb_stb & wb_we & ~ack_r) begin
            for (k = 0; k < DATA_BITS/8; k = k+1)
                if (wb_sel[k]) mem[waddr][k*8 +: 8] <= wb_wdata[k*8 +: 8];
        end
    end

    // Read — registered (matches sky130 macro behaviour: data valid cycle after addr)
    reg [DATA_BITS-1:0] rdata_r;
    always @(posedge clk) begin
        if (wb_cyc & wb_stb & ~wb_we)
            rdata_r <= mem[waddr];
    end
    assign wb_rdata = rdata_r;

    // ── Sky130 macro interface (instantiated when USE_SKY130_MACRO defined) ──
    // Uncomment below and remove the behavioral model when macro LEF/GDS available:
    //
    // sky130_sram_1kbyte_1rw1r_32x256_8 sram_macro (
    //     .clk0   (clk),
    //     .csb0   (~(wb_cyc & wb_stb)),
    //     .web0   (~wb_we),
    //     .wmask0 (wb_sel),
    //     .addr0  (waddr),
    //     .din0   (wb_wdata),
    //     .dout0  (wb_rdata),
    //     .clk1   (clk),   // read port tied to same clock
    //     .csb1   (1'b1),  // read port disabled
    //     .addr1  ({ADDR_BITS{1'b0}}),
    //     .dout1  ()
    // );

endmodule
`default_nettype wire
