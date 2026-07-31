# =============================================================================
# floorplan.tcl — OpenROAD floorplanning for soc_top (PicoRV32 SoC)
# Sky130A HD cells | 38,077 cells | 419,825 µm² synthesis area
# Target: 35% utilization → core ~= 1,200,000 µm² → ~1095 × 1095 µm²
# Run: openroad -exit openroad/floorplan/floorplan.tcl
# =============================================================================

source openroad/common_vars.tcl

puts "\n================================================================="
puts "  FLOORPLAN — $DESIGN_NAME"
puts "  PDK_ROOT : $PDK_ROOT"
puts "=================================================================\n"

# ── Read technology files ─────────────────────────────────────────────────────
puts "Reading LEF files..."
read_lef $TECH_LEF
read_lef $CELL_LEF

# ── Read Liberty ──────────────────────────────────────────────────────────────
puts "Reading Liberty (TT corner)..."
read_liberty $LIB_TT

# ── Read synthesized netlist ──────────────────────────────────────────────────
puts "Reading netlist: $SYNTH_NETLIST"
read_verilog $SYNTH_NETLIST
link_design  $DESIGN_NAME

# ── Read timing constraints ───────────────────────────────────────────────────
puts "Reading SDC: $SDC_FILE"
read_sdc $SDC_FILE

# ── Compute floorplan dimensions ──────────────────────────────────────────────
# Synthesis chip area: 419,825 µm² at sky130_fd_sc_hd (from stat -liberty)
# Target core utilization: 35% → core area = 419825 / 0.35 = 1,199,500 µm²
# Core side: sqrt(1,199,500) ≈ 1095 µm → round up to 1100 µm
# Die = core + 2 × 40 µm boundary → 1180 µm × 1180 µm
set SYNTH_AREA_UM2   419825.15
set TARGET_UTIL      0.35
set CORE_AREA_UM2    [expr {$SYNTH_AREA_UM2 / $TARGET_UTIL}]
set CORE_SIDE        [expr {int(ceil(sqrt($CORE_AREA_UM2) / 10.0) * 10)}]
set BOUNDARY         40
set DIE_SIDE         [expr {$CORE_SIDE + 2 * $BOUNDARY}]

puts "  Synthesis area  : [format %.0f $SYNTH_AREA_UM2] µm²"
puts "  Target util     : [format %.0f [expr {$TARGET_UTIL * 100}]]%"
puts "  Core side       : ${CORE_SIDE} µm"
puts "  Die side        : ${DIE_SIDE} µm"

# ── Initialize floorplan ─────────────────────────────────────────────────────
initialize_floorplan \
    -die_area   "0 0 $DIE_SIDE $DIE_SIDE" \
    -core_area  "$BOUNDARY $BOUNDARY [expr {$DIE_SIDE - $BOUNDARY}] [expr {$DIE_SIDE - $BOUNDARY}]" \
    -site       unithd

# ── Initialize routing tracks (required before place_pins) ───────────────────
make_tracks

# ── IO pin placement ─────────────────────────────────────────────────────────
place_pins \
    -hor_layers met3 \
    -ver_layers met2 \
    -min_distance 2

# ── Tap cell insertion (prevent LU/LD well floating) ─────────────────────────
tapcell \
    -endcap_master   sky130_fd_sc_hd__tap_1 \
    -tapcell_master  sky130_fd_sc_hd__tap_1 \
    -distance        14

# ── Power Distribution Network ────────────────────────────────────────────────
# Sky130A power pin names: VPWR/VGND for core, VPB/VNB for substrate bias
add_global_connection -net VDD -pin_pattern {^VPWR$} -power
add_global_connection -net VDD -pin_pattern {^VPB$}  -power
add_global_connection -net VSS -pin_pattern {^VGND$} -ground
add_global_connection -net VSS -pin_pattern {^VNB$}  -ground

set_voltage_domain -power VDD -ground VSS

define_pdn_grid -name "Core" -voltage_domains "Core"

# Layer met1: horizontal followpin stripes (track power rails)
add_pdn_stripe -followpins -layer met1 -width 0.48

# Layer met4: vertical power stripes
add_pdn_stripe \
    -layer  met4 \
    -width  1.600 \
    -pitch  [expr {$CORE_SIDE / 8.0}] \
    -offset 20.0

# Layer met5: horizontal power stripes
add_pdn_stripe \
    -layer  met5 \
    -width  1.600 \
    -pitch  [expr {$CORE_SIDE / 8.0}] \
    -offset 20.0

# Connect between layers
add_pdn_connect -layers {met1 met4}
add_pdn_connect -layers {met4 met5}

pdngen

# ── Estimate parasitics for pre-placement STA ─────────────────────────────────
estimate_parasitics -placement

# ── Pre-placement timing reports ──────────────────────────────────────────────
set_wire_rc -metal 3

puts "\n=== Pre-placement Setup Timing ==="
report_checks -path_delay max -fields {slew cap input_pins nets} -format full_clock_expanded -digits 3 \
    | tee reports/timing/fp_setup.rpt

puts "\n=== Pre-placement Hold Timing ==="
report_checks -path_delay min -fields {slew cap input_pins nets} -digits 3 \
    | tee reports/timing/fp_hold.rpt

puts "\n=== Design Area ==="
report_design_area | tee reports/synthesis/design_area.rpt

puts "\n=== IO Placement Summary ==="
report_io_placement | tee reports/synthesis/io_placement.rpt

# ── Congestion pre-check ──────────────────────────────────────────────────────
# Run global routing in estimation mode to check for congestion
set_routing_layers -signal {met1 met2 met3 met4 met5} -clock {met3 met4 met5}
global_route -guide_file reports/synthesis/routing_congestion.guide \
             -congestion_iterations 5 \
             -verbose 1 \
    || puts "NOTE: Pre-route congestion check done (warnings expected at this stage)"

puts "\n=== Congestion Report ==="
report_global_routing_congestion | tee reports/synthesis/congestion.rpt

# ── Write floorplan DEF ────────────────────────────────────────────────────────
file mkdir physical
write_def physical/floorplan.def

puts ""
puts "================================================================="
puts "  FLOORPLAN COMPLETE"
puts "  Output   : physical/floorplan.def"
puts "  Die size : $DIE_SIDE x $DIE_SIDE um"
puts "  Core util: [format %.0f [expr {$TARGET_UTIL * 100}]]% target"
puts "================================================================="
