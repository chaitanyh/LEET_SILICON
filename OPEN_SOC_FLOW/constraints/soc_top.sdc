# =============================================================================
# soc_top.sdc — Timing constraints for Open-Source RISC-V SoC
# Target PDK : Sky130 (sky130_fd_sc_hd, 130 nm)
# Clock      : 50 MHz (20 ns period) — conservative for Sky130
# =============================================================================

# ── Clock Definition ──────────────────────────────────────────────────────────
create_clock -name clk -period 20.000 [get_ports clk]

# ── Clock Uncertainty ─────────────────────────────────────────────────────────
# Setup: 0.5 ns (accounts for jitter + skew after CTS)
# Hold:  0.2 ns
set_clock_uncertainty -setup 0.500 [get_clocks clk]
set_clock_uncertainty -hold  0.200 [get_clocks clk]

# ── Input/Output Delays ───────────────────────────────────────────────────────
# Assume 40% of clock period for external I/O paths
set_input_delay  -clock clk -max 8.0 [get_ports {rst_n}]
set_input_delay  -clock clk -min 0.5 [get_ports {rst_n}]

set_output_delay -clock clk -max 8.0 [get_ports {uart_tx_out}]
set_output_delay -clock clk -min 0.5 [get_ports {uart_tx_out}]

set_output_delay -clock clk -max 8.0 [get_ports {gpio_out[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {gpio_out[*]}]

set_output_delay -clock clk -max 8.0 [get_ports {trap}]
set_output_delay -clock clk -min 0.5 [get_ports {trap}]

# ── Driving/Load ──────────────────────────────────────────────────────────────
# Model external driver as 2x sky130_fd_sc_hd__buf_2
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 [get_ports {clk rst_n}]
# 10 fF external load on outputs
set_load 0.010 [get_ports {uart_tx_out trap gpio_out[*]}]

# ── False Paths ───────────────────────────────────────────────────────────────
# Reset is async — no timing arc through reset
set_false_path -from [get_ports rst_n]

# ── Multi-cycle paths ─────────────────────────────────────────────────────────
# PicoRV32 multi-cycle multiplier result (2-cycle operation)
# Adjust if ENABLE_FAST_MUL=1 is used
# set_multicycle_path -setup 2 -from [get_cells u_cpu/alu*] -to [get_cells u_cpu/alu*]
# set_multicycle_path -hold  1 -from [get_cells u_cpu/alu*] -to [get_cells u_cpu/alu*]

# ── Clock Transition Targets ──────────────────────────────────────────────────
set_clock_transition 0.15 [get_clocks clk]

# ── Max Fanout / Transition ───────────────────────────────────────────────────
set_max_fanout  20 [current_design]
set_max_transition 1.0 [current_design]
set_max_capacitance 0.5 [current_design]
