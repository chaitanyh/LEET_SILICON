# =============================================================================
# routing.tcl — FastRoute + TritonRoute + OpenRCX SPEF
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  ROUTING — $DESIGN_NAME"
puts "=================================================================\n"

read_lef $TECH_LEF
read_lef $CELL_LEF
read_liberty $LIB_TT
read_liberty $LIB_FF
read_liberty $LIB_SS

read_def $CTS_DEF
read_sdc $SDC_FILE

set_wire_rc -signal -layer met2
set_wire_rc -clock  -layer met3

set_routing_layers \
    -signal met1-met4 \
    -clock  met3-met5

set_global_routing_layer_adjustment met1 0.65
set_global_routing_layer_adjustment met2 0.15
set_global_routing_layer_adjustment met3 0.15
set_global_routing_layer_adjustment met4 0.10
set_global_routing_layer_adjustment met5 0.05

puts "Running global routing (FastRoute)..."
global_route \
    -guide_file             physical/route.guide \
    -congestion_iterations  20 \
    -congestion_report_file reports/routing/congestion.rpt \
    -verbose

puts "\n=== Global Routing Congestion ==="
if {[info commands report_global_routing_congestion] ne ""} {
    report_global_routing_congestion
}

puts "NOTE: antenna repair skipped (crashes 2024-12-14 binary — antennas checked post-route)"

puts "\nRunning detailed routing (TritonRoute)..."
detailed_route \
    -guide          physical/route.guide \
    -output_drc     reports/routing/drc_violations.rpt \
    -droute_end_iter 64 \
    -verbose

puts "\n=== Post-Route DRC ==="
catch {check_antennas -report_file reports/routing/antenna_violations.rpt}

puts "\nRunning RC extraction (OpenRCX)..."
set rcx_rules "$PDK_ROOT/sky130A/libs.tech/openlane/rcx_rules.lef"
if {[file exists $rcx_rules]} {
    define_process_corner -ext_model_index 0 typical
    extract_parasitics -ext_model_file $rcx_rules
    write_spef physical/soc_top.spef
    puts "SPEF written: physical/soc_top.spef"
} else {
    puts "NOTE: RCX rule file not found at $rcx_rules — skipping SPEF"
}

puts "\n=== Post-Route STA ==="
if {[file exists physical/soc_top.spef]} {
    read_spef physical/soc_top.spef
}
report_checks -path_delay max \
    -fields {slew cap input_pins nets} \
    -format full_clock_expanded -digits 3
report_checks -path_delay min -digits 3
report_wns
report_tns

puts "\n=== Design Area ==="
report_design_area

file mkdir gds
write_def physical/routed.def
write_verilog gls/netlist/soc_top_routed.v

puts ""
puts "================================================================="
puts "  ROUTING COMPLETE: physical/routed.def"
puts "================================================================="
