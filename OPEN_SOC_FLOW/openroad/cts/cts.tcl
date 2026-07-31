# =============================================================================
# cts.tcl — Clock Tree Synthesis for soc_top
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  CLOCK TREE SYNTHESIS (CTS) — $DESIGN_NAME"
puts "=================================================================\n"

read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB_TT
read_liberty $LIB_FF
read_liberty $LIB_SS

read_def $PL_DEF
read_sdc $SDC_FILE

set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

clock_tree_synthesis \
    -root_buf sky130_fd_sc_hd__clkbuf_8 \
    -buf_list {sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16} \
    -sink_clustering_enable \
    -sink_clustering_size     30 \
    -sink_clustering_max_diameter 50.0 \
    -balance_levels

detailed_placement

estimate_parasitics -placement

puts "\nRepairing hold violations post-CTS..."
repair_timing \
    -hold \
    -hold_margin 0.05 \
    -max_passes  5 \
    -verbose

detailed_placement

puts "\n=== Clock Skew ==="
report_clock_skew

puts "\n=== Post-CTS Setup Timing ==="
report_checks -path_delay max \
    -fields {slew cap input_pins nets} \
    -format full_clock_expanded \
    -digits 3

puts "\n=== Post-CTS Hold Timing ==="
report_checks -path_delay min -digits 3

puts "\n=== WNS / TNS ==="
report_wns
report_tns

puts "\n=== Design Area ==="
report_design_area

write_def physical/cts.def
write_verilog gls/netlist/soc_top_cts.v

puts ""
puts "================================================================="
puts "  CTS COMPLETE: physical/cts.def"
puts "================================================================="
