// =============================================================================
// soc_top — Open-Source RISC-V SoC Top Level
//
// Hierarchy:
//   soc_top
//   ├── picorv32          (RV32IMC CPU)
//   ├── wb_interconnect   (1-master Wishbone crossbar)
//   ├── sram_wrapper      (256×32 = 1 KB SRAM; targets sky130 macro)
//   └── uart_tx           (APB UART transmitter, 8N1)
//
// Address Map:
//   0x0000_0000 – 0x0000_03FF  SRAM  (instruction + data)
//   0x1000_0000 – 0x1000_000F  UART TX
//
// Parameters:
//   CLK_FREQ  — design target clock frequency (for baud divisor)
//   BAUD_RATE — UART baud rate
//
// Interface:
//   clk, rst_n  — clock and active-low reset
//   uart_tx_out — serial TX line
//   gpio_out    — 8-bit GPIO (future expansion)
//   trap        — CPU trap signal (halt indicator)
// =============================================================================
`default_nettype none

module soc_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input         clk,
    input         rst_n,

    output        uart_tx_out,
    output [7:0]  gpio_out,
    output        trap
);
    // ── CPU ──────────────────────────────────────────────────────────────────
    wire        cpu_mem_valid, cpu_mem_instr, cpu_mem_ready;
    wire [31:0] cpu_mem_addr,  cpu_mem_wdata, cpu_mem_rdata;
    wire [ 3:0] cpu_mem_wstrb;
    wire [31:0] cpu_irq;
    wire        cpu_mem_la_read, cpu_mem_la_write;
    wire [31:0] cpu_mem_la_addr, cpu_mem_la_wdata;
    wire [ 3:0] cpu_mem_la_wstrb;

    assign cpu_irq = 32'h0;

    picorv32 #(
        .ENABLE_MUL      (1),
        .ENABLE_DIV      (1),
        .ENABLE_IRQ      (1),
        .COMPRESSED_ISA  (1),
        .PROGADDR_RESET  (32'h0000_0000),
        .STACKADDR       (32'h0000_03FC)
    ) u_cpu (
        .clk             (clk),
        .resetn          (rst_n),
        .trap            (trap),
        .mem_valid       (cpu_mem_valid),
        .mem_instr       (cpu_mem_instr),
        .mem_ready       (cpu_mem_ready),
        .mem_addr        (cpu_mem_addr),
        .mem_wdata       (cpu_mem_wdata),
        .mem_wstrb       (cpu_mem_wstrb),
        .mem_rdata       (cpu_mem_rdata),
        .mem_la_read     (cpu_mem_la_read),
        .mem_la_write    (cpu_mem_la_write),
        .mem_la_addr     (cpu_mem_la_addr),
        .mem_la_wdata    (cpu_mem_la_wdata),
        .mem_la_wstrb    (cpu_mem_la_wstrb),
        .pcpi_valid      (),
        .pcpi_insn       (),
        .pcpi_rs1        (),
        .pcpi_rs2        (),
        .pcpi_wr         (1'b0),
        .pcpi_rd         (32'h0),
        .pcpi_wait       (1'b0),
        .pcpi_ready      (1'b0),
        .irq             (cpu_irq),
        .eoi             (),
        .trace_valid     (),
        .trace_data      ()
    );

    // ── Wishbone bus ─────────────────────────────────────────────────────────
    wire [31:0] wb_rdata;
    wire        wb_ack, wb_err;

    // SRAM slave signals
    wire        s0_cyc, s0_stb, s0_we;
    wire [31:0] s0_addr, s0_wdata, s0_rdata;
    wire [ 3:0] s0_sel;
    wire        s0_ack;

    // UART APB slave signals
    wire        s1_psel, s1_penable, s1_pwrite;
    wire [ 3:0] s1_paddr;
    wire [31:0] s1_pwdata, s1_prdata;
    wire        s1_pready;

    wb_interconnect u_bus (
        .clk        (clk),
        .rst_n      (rst_n),
        // Master
        .m_cyc      (cpu_mem_valid),
        .m_stb      (cpu_mem_valid),
        .m_we       (|cpu_mem_wstrb),
        .m_addr     (cpu_mem_addr),
        .m_wdata    (cpu_mem_wdata),
        .m_sel      (cpu_mem_wstrb),
        .m_rdata    (wb_rdata),
        .m_ack      (wb_ack),
        .m_err      (wb_err),
        // SRAM
        .s0_cyc     (s0_cyc),
        .s0_stb     (s0_stb),
        .s0_we      (s0_we),
        .s0_addr    (s0_addr),
        .s0_wdata   (s0_wdata),
        .s0_sel     (s0_sel),
        .s0_rdata   (s0_rdata),
        .s0_ack     (s0_ack),
        // UART
        .s1_psel    (s1_psel),
        .s1_penable (s1_penable),
        .s1_pwrite  (s1_pwrite),
        .s1_paddr   (s1_paddr),
        .s1_pwdata  (s1_pwdata),
        .s1_prdata  (s1_prdata),
        .s1_pready  (s1_pready)
    );

    assign cpu_mem_ready = wb_ack | wb_err;
    assign cpu_mem_rdata = wb_rdata;

    // ── SRAM ─────────────────────────────────────────────────────────────────
    sram_wrapper #(
        .ADDR_BITS (8),
        .DATA_BITS (32)
    ) u_sram (
        .clk     (clk),
        .rst_n   (rst_n),
        .wb_cyc  (s0_cyc),
        .wb_stb  (s0_stb),
        .wb_we   (s0_we),
        .wb_addr (s0_addr[9:0]),
        .wb_wdata(s0_wdata),
        .wb_sel  (s0_sel),
        .wb_rdata(s0_rdata),
        .wb_ack  (s0_ack)
    );

    // ── UART TX ──────────────────────────────────────────────────────────────
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .psel    (s1_psel),
        .penable (s1_penable),
        .pwrite  (s1_pwrite),
        .paddr   (s1_paddr),
        .pwdata  (s1_pwdata),
        .prdata  (s1_prdata),
        .pready  (s1_pready),
        .pslverr (),
        .tx_out  (uart_tx_out),
        .tx_busy ()
    );

    // ── GPIO (stub — future) ─────────────────────────────────────────────────
    assign gpio_out = 8'h00;

endmodule
`default_nettype wire
