# =============================================================================
# placement.tcl — Global + Detailed Placement for soc_top
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  PLACEMENT — $DESIGN_NAME"
puts "=================================================================\n"

# OpenROAD checkpoint flow: read_lef → read_liberty → read_def → read_sdc
# (read_verilog/link_design not needed when reading a full checkpoint DEF)
read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB_TT
read_liberty $LIB_FF
read_liberty $LIB_SS

read_def $FP_DEF
read_sdc $SDC_FILE

set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

# ── Global Placement ──────────────────────────────────────────────────────────
puts "Running global placement..."
global_placement \
    -density         0.35 \
    -pad_left        2 \
    -pad_right       2 \
    -routability_driven \
    -timing_driven

estimate_parasitics -placement

puts "\n=== Post-Global-Placement Timing ==="
report_checks -path_delay max -digits 3 -fields {slew cap nets}
report_wns
report_tns

# ── Repair design ─────────────────────────────────────────────────────────────
puts "\nRepair design (max cap/slew)..."
repair_design \
    -max_wire_length 400 \
    -slew_margin     0.1 \
    -cap_margin      0.1

# ── Detailed Placement ────────────────────────────────────────────────────────
puts "\nDetailed placement..."
detailed_placement

# ── Repair setup timing ───────────────────────────────────────────────────────
puts "\nRepair setup violations..."
repair_timing \
    -setup \
    -setup_margin 0.0 \
    -max_passes   10 \
    -verbose

detailed_placement

puts "\n=== Post-Placement Setup Timing ==="
report_checks -path_delay max -fields {slew cap input_pins nets} \
    -format full_clock_expanded -digits 3

puts "\n=== WNS / TNS ==="
report_wns
report_tns

puts "\n=== Design Area ==="
report_design_area

write_def physical/placed.def
write_verilog gls/netlist/soc_top_placed.v

puts ""
puts "================================================================="
puts "  PLACEMENT COMPLETE: physical/placed.def"
puts "================================================================="
