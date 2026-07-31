# =============================================================================
# common_vars.tcl — Shared variables for all OpenROAD TCL scripts
# Source this at the top of each stage script
# =============================================================================

# ── Design identity ───────────────────────────────────────────────────────────
set DESIGN_NAME  "soc_top"
set CLOCK_PORT   "clk"
set CLOCK_PERIOD  20.000

# ── PDK paths ────────────────────────────────────────────────────────────────
# PDK installed via volare: ~/.volare/volare/sky130/versions/<hash>/sky130A
# PDK_ROOT should be set to the version directory so PDK_ROOT/sky130A exists
# Default: use volare store. Override via env var PDK_ROOT.
if {[info exists ::env(PDK_ROOT)]} {
    set PDK_ROOT $::env(PDK_ROOT)
} else {
    set _volare_ver "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"
    # Windows: USERPROFILE; Linux/macOS: HOME
    set _home [expr {[info exists ::env(USERPROFILE)] ? $::env(USERPROFILE) : $::env(HOME)}]
    set PDK_ROOT "$_home/.volare/volare/sky130/versions/$_volare_ver"
}
set PDK          "sky130A"
set STD_LIB      "sky130_fd_sc_hd"

set TECH_LEF     "$PDK_ROOT/$PDK/libs.ref/$STD_LIB/techlef/${STD_LIB}__nom.tlef"
set CELL_LEF     "$PDK_ROOT/$PDK/libs.ref/$STD_LIB/lef/${STD_LIB}.lef"

# Liberty corners
set LIB_TT       "$PDK_ROOT/$PDK/libs.ref/$STD_LIB/lib/${STD_LIB}__tt_025C_1v80.lib"
set LIB_FF       "$PDK_ROOT/$PDK/libs.ref/$STD_LIB/lib/${STD_LIB}__ff_n40C_1v95.lib"
set LIB_SS       "$PDK_ROOT/$PDK/libs.ref/$STD_LIB/lib/${STD_LIB}__ss_100C_1v60.lib"

# SRAM macro (optional — comment out if not installed)
# set SRAM_LEF   "../../memories/macros/sky130_sram_1kbyte_1rw1r_32x256_8/sky130_sram_1kbyte_1rw1r_32x256_8.lef"
# set SRAM_LIB_TT "../../memories/macros/sky130_sram_1kbyte_1rw1r_32x256_8/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib"

# ── Project paths ─────────────────────────────────────────────────────────────
set PROJECT_ROOT [file normalize "../../"]
set SDC_FILE     "$PROJECT_ROOT/constraints/soc_top.sdc"
# Sky130 technology-mapped netlist (dfflibmap + abc with sky130_fd_sc_hd Liberty)
set SYNTH_NETLIST "$PROJECT_ROOT/gls/netlist/soc_top_sky130.v"

# Physical stage DEFs
set FP_DEF       "$PROJECT_ROOT/physical/floorplan.def"
set PL_DEF       "$PROJECT_ROOT/physical/placed.def"
set CTS_DEF      "$PROJECT_ROOT/physical/cts.def"
set ROUTE_DEF    "$PROJECT_ROOT/physical/routed.def"
set FINAL_DEF    "$PROJECT_ROOT/physical/final.def"
set SPEF_FILE    "$PROJECT_ROOT/physical/soc_top.spef"

# ── Helper proc ───────────────────────────────────────────────────────────────
proc banner {msg} {
    puts "\n[string repeat = 72]"
    puts "  $msg"
    puts "[string repeat = 72]\n"
}
