# =============================================================================
# cts.tcl — Clock Tree Synthesis for soc_top (TritonCTS via OpenROAD)
# Inputs : physical/placed.def
# Outputs: physical/cts.def, reports/timing/cts_*.rpt
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  CLOCK TREE SYNTHESIS (CTS) — $DESIGN_NAME"
puts "=================================================================\n"

# ── Read technology and design files ─────────────────────────────────────────
read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB_TT
read_liberty $LIB_FF
read_liberty $LIB_SS

read_verilog $SYNTH_NETLIST
link_design  $DESIGN_NAME
read_sdc     $SDC_FILE
read_def     $PL_DEF

# ── Wire RC for clock nets ────────────────────────────────────────────────────
set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

# ── Configure CTS ─────────────────────────────────────────────────────────────
clock_tree_synthesis \
    -root_buf          sky130_fd_sc_hd__clkbuf_8 \
    -buf_list          {sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16} \
    -sink_clustering_enable \
    -sink_clustering_size     30 \
    -sink_clustering_max_diameter 50.0 \
    -balance_levels

# ── Post-CTS legalization ─────────────────────────────────────────────────────
detailed_placement

# ── Post-CTS hold repair ──────────────────────────────────────────────────────
estimate_parasitics -placement

puts "\nRepairing hold violations post-CTS..."
repair_timing \
    -hold \
    -hold_margin 0.05 \
    -max_passes  5 \
    -verbose

# Re-legalize after hold repair
detailed_placement

# ── CTS reports ───────────────────────────────────────────────────────────────
puts "\n=== Clock Skew ==="
redirect reports/timing/cts_skew.rpt { report_clock_skew }

puts "\n=== Post-CTS Setup Timing ==="
redirect reports/timing/cts_setup.rpt {
    report_checks -path_delay max \
        -fields {slew cap input_pins nets} \
        -format full_clock_expanded \
        -digits 3
}

puts "\n=== Post-CTS Hold Timing ==="
redirect reports/timing/cts_hold.rpt {
    report_checks -path_delay min -digits 3
}

puts "\n=== WNS / TNS post-CTS ==="
redirect reports/timing/cts_wns.rpt {
    report_wns
    report_tns
}

puts "\n=== Design Area post-CTS ==="
redirect reports/synthesis/cts_area.rpt { report_design_area }

# ── Write CTS DEF ─────────────────────────────────────────────────────────────
write_def physical/cts.def
write_verilog gls/netlist/soc_top_cts.v

puts ""
puts "================================================================="
puts "  CTS COMPLETE"
puts "  Output  : physical/cts.def"
puts "  Skew    : see reports/timing/cts_skew.rpt"
puts "  Closure : see reports/timing/cts_setup.rpt"
puts "================================================================="
