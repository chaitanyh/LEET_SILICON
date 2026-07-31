# =============================================================================
# Makefile — Open-Source RISC-V SoC RTL-to-GDSII Flow
# =============================================================================
# Usage:
#   make help          — list all targets
#   make fetch         — download PDK + IPs
#   make synth         — logic synthesis (Yosys)
#   make gls_func      — functional gate-level simulation (Icarus)
#   make gls_timing    — timing GLS with SDF (Icarus)
#   make pr            — full P&R (OpenROAD via Docker)
#   make drc           — DRC (Magic + KLayout via Docker)
#   make lvs           — LVS (Netgen via Docker)
#   make openlane      — complete flow via OpenLane2 Docker
#   make all           — synth → gls_func (locally executable stages)
#   make clean         — remove generated outputs
# =============================================================================

DESIGN       := soc_top
PROJECT_ROOT := $(shell pwd)
PDK_ROOT     ?= $(HOME)/.volare
PDK          := sky130A
STD_LIB      := sky130_fd_sc_hd
YSCAD        := /c/oss-cad-suite/bin
PATH_EXPORT  := PATH="$(YSCAD):/c/oss-cad-suite/lib:$(PATH)"

# Yosys synthesis script
SYNTH_SCRIPT := configs/yosys/synth_sky130.ys
SYNTH_OUT    := gls/netlist/$(DESIGN)_synth.v

# GLS
TB_GLS       := tb/gls/tb_$(DESIGN)_gls.v
SIM_BIN      := gls/sim_functional

# OpenLane2 Docker image
OPENLANE_IMG := efabless/openlane2:latest
DOCKER_FLAGS := --rm \
                -v $(PROJECT_ROOT):/project \
                -v $(PDK_ROOT):$(PDK_ROOT) \
                -e PDK_ROOT=$(PDK_ROOT) \
                -e PDK=$(PDK)

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN  := \033[0;32m
AMBER  := \033[0;33m
BLUE   := \033[0;34m
RESET  := \033[0m

.PHONY: help fetch synth lint gls_func gls_timing pr drc lvs openlane all clean

# ── Default target ────────────────────────────────────────────────────────────
all: synth gls_func
	@echo -e "$(GREEN)✓ All locally-executable stages complete$(RESET)"

# ── Help ─────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Open-Source RISC-V SoC — RTL-to-GDSII Flow"
	@echo "  ============================================="
	@echo ""
	@echo "  LOCALLY EXECUTABLE (oss-cad-suite):"
	@echo "    make fetch      — download PDK, PicoRV32, SRAM macros"
	@echo "    make lint       — Yosys lint check (no synthesis)"
	@echo "    make synth      — logic synthesis → gls/netlist/soc_top_synth.v"
	@echo "    make gls_func   — functional GLS (Icarus, no SDF)"
	@echo "    make gls_timing — timing GLS with SDF back-annotation"
	@echo "    make formal     — SymbiYosys formal checks"
	@echo ""
	@echo "  REQUIRES DOCKER (openroad/openlane):"
	@echo "    make floorplan  — floorplanning (OpenROAD)"
	@echo "    make place      — placement (OpenROAD)"
	@echo "    make cts        — clock tree synthesis (OpenROAD)"
	@echo "    make route      — routing (OpenROAD)"
	@echo "    make sta        — multi-corner STA (OpenSTA)"
	@echo "    make pr         — full P&R (floorplan→route)"
	@echo "    make drc        — DRC (Magic + KLayout)"
	@echo "    make lvs        — LVS (Netgen)"
	@echo "    make gds        — generate final GDSII"
	@echo "    make openlane   — complete flow via OpenLane2"
	@echo ""
	@echo "  UTILITY:"
	@echo "    make clean      — remove generated files"
	@echo "    make report     — print synthesis report"
	@echo ""

# ── Fetch ─────────────────────────────────────────────────────────────────────
fetch:
	@echo -e "$(BLUE)── Fetching IPs and PDK ──$(RESET)"
	bash scripts/fetch_ip.sh

# ── Lint ──────────────────────────────────────────────────────────────────────
lint:
	@echo -e "$(BLUE)── Yosys RTL Lint ──$(RESET)"
	$(PATH_EXPORT) yosys -p " \
	    read_verilog -sv rtl/core/picorv32.v; \
	    read_verilog -sv rtl/peripherals/uart_tx.v; \
	    read_verilog -sv rtl/memory/sram_wrapper.v; \
	    read_verilog -sv rtl/interconnect/wb_interconnect.v; \
	    read_verilog -sv rtl/soc_top.v; \
	    hierarchy -check -top soc_top; \
	    check"
	@echo -e "$(GREEN)✓ Lint passed$(RESET)"

# ── Synthesis ─────────────────────────────────────────────────────────────────
$(SYNTH_OUT): $(shell find rtl -name "*.v") $(SYNTH_SCRIPT)
	@echo -e "$(BLUE)── Yosys Synthesis ──$(RESET)"
	@mkdir -p gls/netlist reports/synthesis
	cd configs/yosys && $(PATH_EXPORT) PDK_ROOT=$(PDK_ROOT) yosys synth_sky130.ys \
	    2>&1 | tee ../../reports/synthesis/synth.log
	@echo -e "$(GREEN)✓ Synthesis complete → $(SYNTH_OUT)$(RESET)"

synth: $(SYNTH_OUT)

report:
	@echo ""
	@echo "=== Synthesis Report ==="
	@cat reports/synthesis/area_report.txt 2>/dev/null || echo "(Run 'make synth' first)"
	@echo ""

# ── Formal verification ───────────────────────────────────────────────────────
formal:
	@echo -e "$(BLUE)── SymbiYosys Formal ──$(RESET)"
	$(PATH_EXPORT) sby -f scripts/formal/soc_uart_formal.sby 2>&1 | tee reports/gls/formal.log
	@echo -e "$(GREEN)✓ Formal complete$(RESET)"

# ── GLS Functional ────────────────────────────────────────────────────────────
gls_func: $(SYNTH_OUT)
	@echo -e "$(BLUE)── GLS Functional ──$(RESET)"
	@mkdir -p gls/waveforms reports/gls
	bash scripts/gls/run_gls_functional.sh

# ── GLS Timing (needs SDF from routing stage) ────────────────────────────────
gls_timing: $(SYNTH_OUT)
	@echo -e "$(BLUE)── GLS Timing (SDF) ──$(RESET)"
	@if [ ! -f gls/sdf/$(DESIGN).sdf ]; then \
	    echo "ERROR: SDF not found. Run 'make route' first."; exit 1; fi
	@mkdir -p gls/waveforms reports/gls
	$(PATH_EXPORT) iverilog -g2012 -DFUNCTIONAL -DTIMING -DUNIT_DELAY='#1' \
	    -o gls/sim_timing \
	    $(shell [ -f $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_LIB)/verilog/$(STD_LIB).v ] && \
	      echo "-I $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_LIB)/verilog \
	            $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_LIB)/verilog/$(STD_LIB).v") \
	    $(SYNTH_OUT) $(TB_GLS)
	$(PATH_EXPORT) vvp gls/sim_timing \
	    +sdf_file=gls/sdf/$(DESIGN).sdf \
	    +vcd_file=gls/waveforms/gls_timing.vcd \
	    2>&1 | tee reports/gls/gls_timing.log
	@echo -e "$(GREEN)✓ GLS Timing complete$(RESET)"

# ── OpenROAD stages via Docker ────────────────────────────────────────────────
_check_docker:
	@command -v docker >/dev/null 2>&1 || { \
	    echo "ERROR: Docker not found. Install from https://docs.docker.com/get-docker/"; exit 1; }

floorplan: _check_docker $(SYNTH_OUT)
	@echo -e "$(BLUE)── Floorplan (OpenROAD / Docker) ──$(RESET)"
	@mkdir -p physical
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    openroad -exit /project/openroad/floorplan/floorplan.tcl \
	    2>&1 | tee reports/timing/floorplan.log

place: _check_docker
	@echo -e "$(BLUE)── Placement (OpenROAD / Docker) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    openroad -exit /project/openroad/placement/placement.tcl \
	    2>&1 | tee reports/timing/placement.log

cts: _check_docker
	@echo -e "$(BLUE)── CTS (OpenROAD / Docker) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    openroad -exit /project/openroad/cts/cts.tcl \
	    2>&1 | tee reports/timing/cts.log

route: _check_docker
	@echo -e "$(BLUE)── Routing (OpenROAD / Docker) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    openroad -exit /project/openroad/routing/routing.tcl \
	    2>&1 | tee reports/timing/routing.log

sta: _check_docker
	@echo -e "$(BLUE)── STA Sign-off (OpenSTA / Docker) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    openroad -exit /project/openroad/sta/sta_signoff.tcl \
	    2>&1 | tee reports/timing/sta.log

pr: _check_docker synth floorplan place cts route sta
	@echo -e "$(GREEN)✓ Full P&R complete$(RESET)"

# ── DRC / LVS via Docker ─────────────────────────────────────────────────────
drc: _check_docker
	@echo -e "$(BLUE)── DRC (Magic + KLayout) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    bash -c "cd /project && bash physical_verification/magic/run_drc.sh"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    bash -c "cd /project && klayout -b -r physical_verification/klayout/run_klayout_drc.py \
	              -rd input=/project/gds/$(DESIGN).gds \
	              -rd report=/project/reports/pv/klayout_drc.rpt \
	              -rd top_cell=$(DESIGN)"

lvs: _check_docker
	@echo -e "$(BLUE)── LVS (Magic extraction + Netgen) ──$(RESET)"
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    bash -c "cd /project && bash physical_verification/magic/run_lvs.sh"

# ── GDS generation via Docker ─────────────────────────────────────────────────
gds: _check_docker
	@echo -e "$(BLUE)── GDS Generation ──$(RESET)"
	@mkdir -p gds
	docker run $(DOCKER_FLAGS) $(OPENLANE_IMG) \
	    bash -c "cd /project && klayout -b -r physical_verification/klayout/merge_gds.py"

# ── OpenLane2 complete flow ───────────────────────────────────────────────────
openlane: _check_docker
	@echo -e "$(BLUE)── OpenLane2 Complete Flow ──$(RESET)"
	@mkdir -p openlane/runs
	docker run $(DOCKER_FLAGS) \
	    -v $(PROJECT_ROOT)/openlane/runs:/project/openlane/runs \
	    $(OPENLANE_IMG) \
	    openlane /project/configs/openlane/config.json \
	    2>&1 | tee openlane/openlane.log
	@echo -e "$(GREEN)✓ OpenLane2 complete — see openlane/runs/$(RESET)"

# ── Clean ─────────────────────────────────────────────────────────────────────
clean:
	rm -f  $(SYNTH_OUT) gls/sim_functional gls/sim_timing
	rm -f  gls/waveforms/*.vcd gls/sdf/*.sdf
	rm -rf physical/*.def physical/*.spef physical/*.guide
	rm -rf gds/*.gds gds/*.lef gds/*.spef
	rm -rf reports/synthesis/* reports/timing/* reports/pv/* reports/gls/*
	rm -rf openlane/runs/
	@echo "✓ Clean complete"
