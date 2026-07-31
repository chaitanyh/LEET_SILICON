// =============================================================================
// UART Transmitter — APB-lite slave, 8N1, parameterised baud divisor
// =============================================================================
`default_nettype none

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200,
    parameter DIVISOR   = CLK_FREQ / BAUD_RATE   // 434 @ 50 MHz / 115200
)(
    input            clk,
    input            rst_n,

    // APB slave
    input            psel,
    input            penable,
    input            pwrite,
    input  [3:0]     paddr,
    input  [31:0]    pwdata,
    output [31:0]    prdata,
    output           pready,
    output           pslverr,

    // Serial output
    output reg       tx_out,
    output           tx_busy
);
    // ── Register map ─────────────────────────────────────────────────────────
    // 0x0 : TX_DATA  [7:0]  write-only  — write byte to transmit
    // 0x4 : TX_STAT  [0]    read-only   — 0=idle, 1=busy

    // ── Baud generator ───────────────────────────────────────────────────────
    reg  [$clog2(DIVISOR+1)-1:0] baud_cnt;
    wire baud_tick = (baud_cnt == 0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_cnt <= DIVISOR - 1;
        else if (baud_cnt == 0)
            baud_cnt <= DIVISOR - 1;
        else
            baud_cnt <= baud_cnt - 1;
    end

    // ── Shift register (start + 8 data + stop = 10 bits) ─────────────────────
    reg  [9:0]  shift_reg;
    reg  [3:0]  bit_cnt;
    reg         busy;

    assign tx_busy = busy;

    // APB write fires a new TX when idle
    wire apb_wr_txdata = psel & penable & pwrite & (paddr[3:2] == 2'b00);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'h3FF;
            bit_cnt   <= 4'd0;
            busy      <= 1'b0;
            tx_out    <= 1'b1;
        end else begin
            if (!busy && apb_wr_txdata) begin
                // Load: start(0) + data[7:0] + stop(1)
                shift_reg <= {1'b1, pwdata[7:0], 1'b0};
                bit_cnt   <= 4'd10;
                busy      <= 1'b1;
            end else if (busy && baud_tick) begin
                tx_out    <= shift_reg[0];
                shift_reg <= {1'b1, shift_reg[9:1]};
                if (bit_cnt == 4'd1) begin
                    busy    <= 1'b0;
                    bit_cnt <= 4'd0;
                end else begin
                    bit_cnt <= bit_cnt - 1;
                end
            end
        end
    end

    // ── APB response ─────────────────────────────────────────────────────────
    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    assign prdata  = (paddr[3:2] == 2'b01) ? {31'h0, busy} : 32'h0;

endmodule
`default_nettype wire
