// =============================================================================
// Wishbone Interconnect — 1 Master × 3 Slaves (memory-mapped)
//
// Address map (32-bit byte addressing):
//   0x0000_0000 – 0x0000_03FF  : SRAM (1 KB)
//   0x1000_0000 – 0x1000_000F  : UART TX
//   0x2000_0000 – 0x2000_000F  : GPIO (future)
// =============================================================================
`default_nettype none

module wb_interconnect (
    input          clk,
    input          rst_n,

    // Master port (from CPU)
    input          m_cyc,
    input          m_stb,
    input          m_we,
    input  [31:0]  m_addr,
    input  [31:0]  m_wdata,
    input  [ 3:0]  m_sel,
    output [31:0]  m_rdata,
    output         m_ack,
    output         m_err,

    // Slave 0 — SRAM
    output         s0_cyc,
    output         s0_stb,
    output         s0_we,
    output [31:0]  s0_addr,
    output [31:0]  s0_wdata,
    output [ 3:0]  s0_sel,
    input  [31:0]  s0_rdata,
    input          s0_ack,

    // Slave 1 — UART TX (APB-bridge)
    output         s1_psel,
    output         s1_penable,
    output         s1_pwrite,
    output [ 3:0]  s1_paddr,
    output [31:0]  s1_pwdata,
    input  [31:0]  s1_prdata,
    input          s1_pready
);
    // ── Address decode ────────────────────────────────────────────────────────
    wire sel_s0 = (m_addr[31:10] == 22'h000000);   // 0x000000xx (1KB)
    wire sel_s1 = (m_addr[31:16] == 16'h1000);      // 0x1000xxxx (UART)

    // ── SRAM slave ────────────────────────────────────────────────────────────
    assign s0_cyc   = m_cyc & sel_s0;
    assign s0_stb   = m_stb & sel_s0;
    assign s0_we    = m_we;
    assign s0_addr  = m_addr;
    assign s0_wdata = m_wdata;
    assign s0_sel   = m_sel;

    // ── UART APB bridge ───────────────────────────────────────────────────────
    // WB→APB: psel asserted with stb, penable on next cycle
    reg apb_phase;  // 0=setup, 1=access
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) apb_phase <= 1'b0;
        else if (sel_s1 && m_cyc && m_stb && !apb_phase)
            apb_phase <= 1'b1;
        else if (s1_pready)
            apb_phase <= 1'b0;
    end
    assign s1_psel    = m_cyc & m_stb & sel_s1;
    assign s1_penable = apb_phase;
    assign s1_pwrite  = m_we;
    assign s1_paddr   = m_addr[3:0];
    assign s1_pwdata  = m_wdata;

    // ── Mux read data / ack ───────────────────────────────────────────────────
    wire s1_ack = s1_psel & s1_penable & s1_pready;

    assign m_rdata = sel_s0 ? s0_rdata :
                     sel_s1 ? s1_prdata :
                               32'hDEAD_BEEF;
    assign m_ack   = sel_s0 ? s0_ack :
                     sel_s1 ? s1_ack :
                               (m_cyc & m_stb);  // default: instant ack (error region)
    assign m_err   = m_cyc & m_stb & !sel_s0 & !sel_s1;

endmodule
`default_nettype wire
