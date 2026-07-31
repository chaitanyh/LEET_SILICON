# =============================================================================
# routing.tcl — FastRoute (global) + TritonRoute (detailed) + OpenRCX (SPEF)
# Design : soc_top | Technology: sky130A
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  ROUTING — $DESIGN_NAME"
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
read_def     $CTS_DEF

# ── Wire RC for pre-route STA ─────────────────────────────────────────────────
set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

# ── Routing layer configuration ───────────────────────────────────────────────
set_routing_layers \
    -signal {met1 met2 met3 met4} \
    -clock  {met3 met4 met5}

# ── Layer adjustments (reduce congestion on local layers) ────────────────────
set_global_routing_layer_adjustment met1 0.65
set_global_routing_layer_adjustment met2 0.15
set_global_routing_layer_adjustment met3 0.15
set_global_routing_layer_adjustment met4 0.10
set_global_routing_layer_adjustment met5 0.05

# ── Global Routing (FastRoute) ────────────────────────────────────────────────
puts "Running global routing (FastRoute)..."
global_route \
    -guide_file             physical/route.guide \
    -congestion_iterations  20 \
    -congestion_report_file reports/routing/congestion.rpt \
    -verbose                1

puts "\n=== Global Routing Congestion ==="
redirect reports/routing/grt_congestion.rpt { report_global_routing_congestion }

# ── Repair antenna violations (pre-route) ────────────────────────────────────
repair_antennas sky130_fd_sc_hd__diode_2 \
    || puts "NOTE: antenna repair skipped (diode not found or no violations)"

# ── Detailed Routing (TritonRoute) ────────────────────────────────────────────
puts "\nRunning detailed routing (TritonRoute)..."
detailed_route \
    -guide          physical/route.guide \
    -output_drc     reports/routing/drc_violations.rpt \
    -droute_end_iter 64 \
    -verbose        1

# ── Check DRC after routing ───────────────────────────────────────────────────
puts "\n=== Post-Route DRC ==="
check_antennas -report_file reports/routing/antenna_violations.rpt || true

# ── Parasitic Extraction (OpenRCX) ───────────────────────────────────────────
puts "\nRunning RC extraction (OpenRCX)..."
set rcx_rules "$PDK_ROOT/sky130A/libs.tech/openlane/rcx_rules.lef"
if {[file exists $rcx_rules]} {
    define_process_corner -ext_model_index 0 typical
    extract_parasitics -ext_model_file $rcx_rules
} else {
    puts "NOTE: RCX rule file not found at $rcx_rules — skipping SPEF extraction"
}

# Write SPEF (will be empty if RCX skipped, but file must exist for STA)
if {[file exists $rcx_rules]} {
    write_spef physical/soc_top.spef
}

# ── Post-route STA (wire RC estimate if no SPEF) ──────────────────────────────
puts "\n=== Post-Route STA ==="
if {[file exists physical/soc_top.spef]} {
    read_spef physical/soc_top.spef
}

puts "\n--- TT Corner ---"
redirect reports/timing/route_setup_tt.rpt {
    report_checks -path_delay max \
        -fields {slew cap input_pins nets} \
        -format full_clock_expanded \
        -digits 3
}
redirect reports/timing/route_hold_tt.rpt {
    report_checks -path_delay min -digits 3
}

puts "\n=== WNS / TNS Summary ==="
report_wns
report_tns

puts "\n=== Design Area Final ==="
redirect reports/routing/final_area.rpt { report_design_area }

# ── Write outputs ─────────────────────────────────────────────────────────────
file mkdir gds
write_def physical/routed.def
write_verilog gls/netlist/soc_top_routed.v

puts ""
puts "================================================================="
puts "  ROUTING COMPLETE"
puts "  Routed DEF : physical/routed.def"
puts "  SPEF       : physical/soc_top.spef"
puts "  Netlist    : gls/netlist/soc_top_routed.v"
puts "  DRC        : reports/routing/drc_violations.rpt"
puts "================================================================="
