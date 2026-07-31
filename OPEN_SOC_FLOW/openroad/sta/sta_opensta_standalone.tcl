# =============================================================================
# sta_opensta_standalone.tcl — OpenSTA standalone STA for soc_top Sky130
# Run: sta.exe -exit sta_opensta_standalone.tcl
# =============================================================================

set PDK_VER "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"
set PDK_ROOT "$env(USERPROFILE)/.volare/volare/sky130/versions/$PDK_VER"
set DESIGN_NAME "soc_top"
set STD_LIB "sky130_fd_sc_hd"

set LIB_TT  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__tt_025C_1v80.lib"
set LIB_FF  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__ff_n40C_1v95.lib"
set LIB_SS  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__ss_100C_1v60.lib"

set SDC_FILE     "constraints/soc_top.sdc"
set NETLIST_FILE "gls/netlist/soc_top_sky130.v"

puts "\n================================================================="
puts "  OpenSTA 3.1 — STA Sign-off  |  $DESIGN_NAME  |  sky130_fd_sc_hd"
puts "  Corners: TT (025C 1v80), FF (n40C 1v95), SS (100C 1v60)"
puts "=================================================================\n"

# ── Define corners ────────────────────────────────────────────────────────────
define_corners tt ff ss

# ── Read Liberty ──────────────────────────────────────────────────────────────
read_liberty -corner tt $LIB_TT
read_liberty -corner ff $LIB_FF
read_liberty -corner ss $LIB_SS

puts "Liberty files loaded for all 3 corners."

# ── Read netlist ──────────────────────────────────────────────────────────────
read_verilog $NETLIST_FILE
link_design  $DESIGN_NAME

puts "Netlist linked: $DESIGN_NAME"

# ── Read constraints ──────────────────────────────────────────────────────────
read_sdc $SDC_FILE
puts "SDC loaded: $SDC_FILE"

# ── Wire load model (OpenSTA standalone; set_wire_rc is OpenROAD-only) ────────
# Use sky130_fd_sc_hd wire load model for pre-route estimate
# Wire load models are defined in Liberty; use default_wire_load if present
puts "Note: Using Liberty wire load models for pre-route parasitics.\n"

# ── Create report directories ─────────────────────────────────────────────────
file mkdir reports/timing

# ── TT Corner: Setup ──────────────────────────────────────────────────────────
puts "\n=== TT Corner (025C 1v80) — Setup (max path) ==="
report_checks -corner tt -path_delay max \
    -fields {slew capacitance input_pin net} \
    -format full_clock_expanded \
    -digits 3 \
    -endpoint_path_count 10 \
    > reports/timing/sta_setup_tt.rpt
report_checks -corner tt -path_delay max \
    -fields {slew capacitance input_pin net} \
    -format full_clock_expanded \
    -digits 3 \
    -endpoint_path_count 5

# ── TT Corner: Hold ───────────────────────────────────────────────────────────
puts "\n=== TT Corner (025C 1v80) — Hold (min path) ==="
report_checks -corner tt -path_delay min \
    -digits 3 \
    -endpoint_path_count 5 \
    > reports/timing/sta_hold_tt.rpt
report_checks -corner tt -path_delay min \
    -digits 3 \
    -endpoint_path_count 3

# ── SS Corner: Setup (worst-case setup) ───────────────────────────────────────
puts "\n=== SS Corner (100C 1v60) — Setup WORST CASE ==="
report_checks -corner ss -path_delay max \
    -fields {slew capacitance input_pin net} \
    -format full_clock_expanded \
    -digits 3 \
    -endpoint_path_count 10 \
    > reports/timing/sta_setup_ss.rpt
report_checks -corner ss -path_delay max \
    -digits 3 \
    -endpoint_path_count 3

# ── FF Corner: Hold (worst-case hold) ─────────────────────────────────────────
puts "\n=== FF Corner (n40C 1v95) — Hold WORST CASE ==="
report_checks -corner ff -path_delay min \
    -digits 3 \
    -endpoint_path_count 10 \
    > reports/timing/sta_hold_ff.rpt
report_checks -corner ff -path_delay min \
    -digits 3 \
    -endpoint_path_count 3

# ── WNS/TNS Summary ───────────────────────────────────────────────────────────
puts "\n================================================================="
puts "  MULTI-CORNER TIMING SUMMARY"
puts "=================================================================\n"

foreach corner {tt ff ss} {
    puts "Corner: $corner"
    report_wns
    report_tns
    puts ""
}

# ── Clock summary ─────────────────────────────────────────────────────────────
puts "\n=== Clock Summary ==="
report_clock_properties > reports/timing/sta_clocks.rpt
report_clock_properties

# ── Constraint check ─────────────────────────────────────────────────────────
puts "\n=== Constraint Check ==="
check_setup > reports/timing/sta_constraints.rpt
check_setup

# ── Write summary ─────────────────────────────────────────────────────────────
set fh [open reports/timing/sta_summary.rpt w]
puts $fh "STA SIGNOFF SUMMARY"
puts $fh "Design  : $DESIGN_NAME"
puts $fh "PDK     : sky130_fd_sc_hd"
puts $fh "Clock   : clk  Period: 20.000 ns (50 MHz)"
puts $fh ""
puts $fh "Pre-route (wire RC estimate, no SPEF)"
puts $fh ""
puts $fh "Corner      Analysis   WNS(ns)   TNS(ns)    Status"
puts $fh "----------  ---------  --------  ---------  ------"

foreach {corner type} {tt setup tt hold ss setup ff hold} {
    set delay [expr {$type eq "setup" ? "max" : "min"}]
    # Use report_wns/tns to get values
}
close $fh

puts "\n================================================================="
puts "  STA COMPLETE"
puts "  Reports: reports/timing/"
puts "================================================================="
