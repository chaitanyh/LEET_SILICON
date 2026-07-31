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
# Synthesis chip area: 419,825 µm² at sky130_fd_sc_hd
# Target core utilization: 35% → core area = 419825 / 0.35 = 1,199,500 µm²
# Core side: sqrt(1,199,500) ≈ 1095 µm → round up to 1100 µm
# Die = core + 2 × 40 µm boundary → 1180 µm × 1180 µm
# Actual placed area after tap/endcap insertion is ~631K um2 (tap cells add ~50%)
# Size for ~36% utilization to give router headroom: core 1320x1320, die 1400x1400 um
set BOUNDARY         40.0
set CORE_SIDE_UM     1320.0
set DIE_SIDE         [expr {$CORE_SIDE_UM + 2 * $BOUNDARY}]
set TARGET_UTIL      0.36

puts "  Synthesis area: $SYNTH_AREA_UM2 µm²"
puts "  Core side     : $CORE_SIDE_UM µm"
puts "  Die side      : $DIE_SIDE µm (with $BOUNDARY µm boundary)"

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
add_global_connection -net VDD -pin_pattern {^VPWR$} -power
add_global_connection -net VDD -pin_pattern {^VPB$}  -power
add_global_connection -net VSS -pin_pattern {^VGND$} -ground
add_global_connection -net VSS -pin_pattern {^VNB$}  -ground

set_voltage_domain -power VDD -ground VSS

define_pdn_grid -name "Core" -voltage_domains "Core"

add_pdn_stripe -followpins -layer met1 -width 0.48

add_pdn_stripe \
    -layer  met4 \
    -width  1.6 \
    -pitch  50.0 \
    -offset 10.0

add_pdn_connect -layers {met1 met4}
add_pdn_connect -layers {met4 met5}

pdngen

# ── Wire RC estimate for pre-floorplan STA ────────────────────────────────────
set_wire_rc -layer met3
estimate_parasitics -placement

puts "\n=== Pre-placement Timing (wire RC estimate) ==="
report_checks -path_delay max -digits 3
report_wns
report_tns

puts "\n=== Design Area ==="
report_design_area

# ── Write floorplan DEF ────────────────────────────────────────────────────────
file mkdir physical
file mkdir reports/timing
file mkdir reports/synthesis
file mkdir reports/routing
file mkdir reports/pv
write_def physical/floorplan.def

puts ""
puts "================================================================="
puts "  FLOORPLAN COMPLETE"
puts "  Output   : physical/floorplan.def"
puts "  Die size : $DIE_SIDE x $DIE_SIDE um"
puts "  Core util: [format %.0f [expr {$TARGET_UTIL * 100}]]% target"
puts "================================================================="
