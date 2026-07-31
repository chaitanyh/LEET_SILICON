# =============================================================================
# placement.tcl — Global + Detailed Placement for soc_top
# Inputs: physical/floorplan.def + sky130_fd_sc_hd Liberty + netlist
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  PLACEMENT — $DESIGN_NAME"
puts "=================================================================\n"

# ── Read technology files ─────────────────────────────────────────────────────
read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB_TT
read_liberty $LIB_FF
read_liberty $LIB_SS

# ── Read netlist and DEF ──────────────────────────────────────────────────────
read_verilog $SYNTH_NETLIST
link_design  $DESIGN_NAME
read_sdc     $SDC_FILE
read_def     $FP_DEF

# ── Set wire RC models ────────────────────────────────────────────────────────
set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

# ── Global Placement ──────────────────────────────────────────────────────────
puts "Running global placement (density=0.35, timing+routability driven)..."
global_placement \
    -density              0.35 \
    -pad_left             2 \
    -pad_right            2 \
    -routability_driven \
    -timing_driven

# ── Estimate parasitics after global placement ────────────────────────────────
estimate_parasitics -placement

puts "\n=== Post-Global-Placement Timing ==="
report_checks -path_delay max -digits 3 -fields {slew cap nets} \
    | tee reports/timing/gpl_setup.rpt
report_wns  | tee -a reports/timing/gpl_setup.rpt
report_tns  | tee -a reports/timing/gpl_setup.rpt

# ── Repair design (buffer insertion, gate sizing for slew/cap) ────────────────
puts "\nRepair design for max cap/slew violations..."
repair_design \
    -max_wire_length 400 \
    -slew_margin     0.1 \
    -cap_margin      0.1

# ── Detailed Placement (legalization + optimization) ──────────────────────────
puts "\nRunning detailed placement (legalization)..."
detailed_placement

# ── Repair timing: setup violations ──────────────────────────────────────────
puts "\nRepair timing: setup violations..."
repair_timing \
    -setup \
    -setup_margin    0.0 \
    -max_passes      10 \
    -verbose

# ── Re-legalize after ECO ─────────────────────────────────────────────────────
detailed_placement

# ── Post-placement checks ─────────────────────────────────────────────────────
check_placement -verbose | tee reports/synthesis/placement_check.rpt

# ── Final post-placement timing ───────────────────────────────────────────────
estimate_parasitics -placement

puts "\n=== Post-Placement Setup Timing ==="
report_checks -path_delay max -fields {slew cap input_pins nets} \
    -format full_clock_expanded -digits 3 \
    | tee reports/timing/pl_setup.rpt

puts "\n=== Post-Placement Hold Timing ==="
report_checks -path_delay min -digits 3 | tee reports/timing/pl_hold.rpt

puts "\n=== WNS / TNS ==="
report_wns | tee reports/timing/pl_wns.rpt
report_tns | tee -a reports/timing/pl_wns.rpt

puts "\n=== Design Area After Placement ==="
report_design_area | tee reports/synthesis/placed_area.rpt

# ── Write output ──────────────────────────────────────────────────────────────
write_def physical/placed.def
write_verilog gls/netlist/soc_top_placed.v

puts ""
puts "================================================================="
puts "  PLACEMENT COMPLETE"
puts "  Output : physical/placed.def"
puts "================================================================="
