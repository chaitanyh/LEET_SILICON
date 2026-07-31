# =============================================================================
# sta_signoff.tcl — Multi-corner sign-off STA for soc_top
# Runs inside OpenROAD (embedded STA) after routing
# =============================================================================

# ── Detect execution context ──────────────────────────────────────────────────
set is_openroad [expr {[info commands read_def] ne ""}]

if {$is_openroad} {
    source openroad/common_vars.tcl
    puts "Running in OpenROAD context"
    read_lef $TECH_LEF
    read_lef $CELL_LEF
    read_def $ROUTE_DEF
} else {
    puts "Running in OpenSTA standalone context"
    set PDK_VER "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"
    set _home [expr {[info exists ::env(USERPROFILE)] ? $::env(USERPROFILE) : $::env(HOME)}]
    set PDK_ROOT "$_home/.volare/volare/sky130/versions/$PDK_VER"
    set DESIGN_NAME "soc_top"
    set STD_LIB "sky130_fd_sc_hd"
    set LIB_TT  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__tt_025C_1v80.lib"
    set LIB_FF  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__ff_n40C_1v95.lib"
    set LIB_SS  "$PDK_ROOT/sky130A/libs.ref/$STD_LIB/lib/${STD_LIB}__ss_100C_1v60.lib"
    set SDC_FILE "constraints/soc_top.sdc"
    set SYNTH_NETLIST "gls/netlist/soc_top_routed.v"
    set SPEF_FILE "physical/soc_top.spef"
}

puts "\n================================================================="
puts "  STA SIGN-OFF — $DESIGN_NAME"
puts "  Corners: TT (025C 1v80), FF (n40C 1v95), SS (100C 1v60)"
puts "=================================================================\n"

# ── Define PVT corners ────────────────────────────────────────────────────────
define_corners tt ff ss

# ── Read Liberty for each corner ─────────────────────────────────────────────
read_liberty -corner tt $LIB_TT
read_liberty -corner ff $LIB_FF
read_liberty -corner ss $LIB_SS

# ── Read netlist ──────────────────────────────────────────────────────────────
read_verilog $SYNTH_NETLIST
link_design  $DESIGN_NAME

# ── Read constraints ──────────────────────────────────────────────────────────
read_sdc $SDC_FILE

# ── Read SPEF parasitics ─────────────────────────────────────────────────────
if {[file exists $SPEF_FILE]} {
    read_spef -corner tt $SPEF_FILE
    read_spef -corner ff $SPEF_FILE
    read_spef -corner ss $SPEF_FILE
    puts "SPEF loaded: $SPEF_FILE"
} else {
    puts "NOTE: SPEF not found — using wire RC models"
    set_wire_rc -signal -layer met2
    set_wire_rc -clock  -layer met3
    estimate_parasitics -placement
}

file mkdir reports/timing

# ── TT Corner ────────────────────────────────────────────────────────────────
puts "\n=== TT Corner — Setup ==="
redirect reports/timing/sta_setup_tt.rpt {
    report_checks -corner tt -path_delay max \
        -fields {slew cap input_pins nets} \
        -format full_clock_expanded -digits 3 -path_count 10
}

puts "\n=== TT Corner — Hold ==="
redirect reports/timing/sta_hold_tt.rpt {
    report_checks -corner tt -path_delay min -digits 3 -path_count 5
}

# ── SS Corner ────────────────────────────────────────────────────────────────
puts "\n=== SS Corner — Setup (worst) ==="
redirect reports/timing/sta_setup_ss.rpt {
    report_checks -corner ss -path_delay max \
        -fields {slew cap input_pins nets} \
        -format full_clock_expanded -digits 3 -path_count 10
}

# ── FF Corner ────────────────────────────────────────────────────────────────
puts "\n=== FF Corner — Hold (worst) ==="
redirect reports/timing/sta_hold_ff.rpt {
    report_checks -corner ff -path_delay min -digits 3 -path_count 10
}

# ── Multi-corner WNS/TNS summary ─────────────────────────────────────────────
puts "\n================================================================="
puts "  MULTI-CORNER TIMING SUMMARY"
puts "=================================================================\n"

foreach corner {tt ff ss} {
    puts "Corner: $corner"
    report_wns -corner $corner
    report_tns -corner $corner
    puts ""
}

# ── Clock and constraint reports ──────────────────────────────────────────────
redirect reports/timing/sta_clocks.rpt { report_clocks }
redirect reports/timing/sta_constraints.rpt { check_timing }

# ── Signoff summary ───────────────────────────────────────────────────────────
puts "\n================================================================="
puts "  SIGNOFF SUMMARY"
puts "================================================================="

proc get_wns {min_max corner_name} {
    set paths [find_timing_paths -path_delay $min_max -corner $corner_name -sort_by_slack -endpoint_path_count 1]
    if {[llength $paths] == 0} { return 0.0 }
    return [get_property [lindex $paths 0] slack]
}

set wns_tt_setup [get_wns max tt]
set wns_ss_setup [get_wns max ss]
set wns_ff_hold  [get_wns min ff]

foreach {label val} [list \
    "Setup TT (WNS)" $wns_tt_setup \
    "Setup SS (WNS)" $wns_ss_setup \
    "Hold  FF (WNS)" $wns_ff_hold  \
] {
    if {$val >= 0} {
        puts "  PASS  $label : [format {%+.3f} $val] ns"
    } else {
        puts "  FAIL  $label : [format {%+.3f} $val] ns  <- VIOLATION"
    }
}

set summary_file reports/timing/sta_signoff_summary.rpt
set fh [open $summary_file w]
puts $fh "STA SIGNOFF SUMMARY — $DESIGN_NAME"
puts $fh "Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M}]"
puts $fh ""
puts $fh "Clock: clk  Period: 20.000 ns (50 MHz)"
puts $fh ""
puts $fh "Corner      Slack(ns)  Status"
puts $fh "----------  ---------  -------"
foreach {corner slack} [list \
    "TT setup" $wns_tt_setup \
    "SS setup" $wns_ss_setup \
    "FF hold " $wns_ff_hold  \
] {
    set status [expr {$slack >= 0 ? "PASS" : "FAIL"}]
    puts $fh [format "%-10s  %+8.3f   %s" $corner $slack $status]
}
close $fh

puts "\n  Summary : $summary_file"
puts "================================================================="
