#!/usr/bin/env python3
"""
run_drc_sky130.py — KLayout DRC for soc_top using Sky130A rules
Uses KLayout Python API (klayout.db) — no GUI needed.
Runs: sky130A.lydrc (standard DRC deck from PDK)

Usage: py -3.11 physical_verification/klayout/run_drc_sky130.py [--gds GDS_FILE]
"""
import sys, os, argparse
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent.parent
PDK_VER = "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"
PDK_ROOT = Path.home() / ".volare/volare/sky130/versions" / PDK_VER / "sky130A"
DRC_DECK = PDK_ROOT / "libs.tech/klayout/drc/sky130A.lydrc"
DRC_DECK_MR = PDK_ROOT / "libs.tech/klayout/drc/sky130A_mr.drc"
GDS_DEFAULT = PROJECT_ROOT / "gds/soc_top.gds"
RPT_DIR = PROJECT_ROOT / "reports/pv"

def main():
    parser = argparse.ArgumentParser(description="KLayout DRC for soc_top")
    parser.add_argument("--gds", default=str(GDS_DEFAULT), help="GDS file to check")
    parser.add_argument("--deck", default=str(DRC_DECK), help="DRC deck (.lydrc or .drc)")
    parser.add_argument("--rpt", default=str(RPT_DIR / "klayout_drc.xml"), help="Output XML report")
    args = parser.parse_args()

    print("=" * 65)
    print("  KLayout DRC — soc_top")
    print(f"  GDS   : {args.gds}")
    print(f"  Deck  : {args.deck}")
    print("=" * 65)

    # ── Import KLayout ────────────────────────────────────────────────────────
    try:
        import klayout.db as db
        import klayout.lay as lay
        print(f"  KLayout: {db.__version__}")
    except ImportError:
        print("ERROR: klayout not installed. Run: py -3.11 -m pip install klayout")
        sys.exit(1)

    # ── Check inputs ──────────────────────────────────────────────────────────
    gds_path = Path(args.gds)
    deck_path = Path(args.deck)
    RPT_DIR.mkdir(parents=True, exist_ok=True)
    rpt_path = Path(args.rpt)

    if not gds_path.exists():
        print(f"\nWARNING: GDS not found: {gds_path}")
        print("  DRC requires a routed GDS from OpenROAD/KLayout write_gds")
        print("  Running DRC deck syntax check only...")
        check_deck_only(deck_path)
        write_placeholder_report(rpt_path, gds_path, deck_path)
        return

    if not deck_path.exists():
        print(f"WARNING: Primary DRC deck not found: {deck_path}")
        if DRC_DECK_MR.exists():
            deck_path = DRC_DECK_MR
            print(f"  Falling back to: {deck_path}")
        else:
            print("ERROR: No DRC deck found in PDK")
            sys.exit(1)

    # ── Load GDS ──────────────────────────────────────────────────────────────
    print(f"\nLoading GDS: {gds_path} ...", flush=True)
    layout = db.Layout()
    layout.read(str(gds_path))
    top_cells = [c.name for c in layout.top_cells()]
    print(f"  Top cells: {top_cells}")
    print(f"  Layers   : {len(list(layout.layer_indexes()))}")

    # ── Run DRC using RBA (Ruby-based) or Python batch mode ──────────────────
    # KLayout's DRC engine can be invoked via the 'rdb' module in batch
    print("\nRunning DRC...", flush=True)

    # Use KLayout's batch DRC via subprocess (most reliable for .lydrc files)
    import subprocess
    klayout_exe = find_klayout_exe()

    if klayout_exe and deck_path.suffix == ".lydrc":
        # Run via KLayout executable in batch mode
        cmd = [
            klayout_exe, "-b",
            "-r", str(deck_path),
            "-rd", f"input={gds_path}",
            "-rd", f"report={rpt_path}",
            "-rd", f"cell={top_cells[0] if top_cells else 'soc_top'}",
        ]
        print(f"  Command: {' '.join(cmd[:4])} ...")
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            print(result.stdout[-2000:] if result.stdout else "")
            if result.stderr:
                print("STDERR:", result.stderr[-500:])
        except subprocess.TimeoutExpired:
            print("DRC timed out after 300s")
        except FileNotFoundError:
            print(f"KLayout executable not found: {klayout_exe}")
            run_python_drc(layout, top_cells, gds_path, rpt_path)
    else:
        # Fall back to Python API DRC
        run_python_drc(layout, top_cells, gds_path, rpt_path)

    # ── Parse and summarize results ───────────────────────────────────────────
    if rpt_path.exists():
        summarize_report(rpt_path)
    print(f"\nDRC Report: {rpt_path}")

def run_python_drc(layout, top_cells, gds_path, rpt_path):
    """Run basic geometric DRC checks using KLayout Python API."""
    import klayout.db as db
    import klayout.rdb as rdb_mod

    print("\nRunning Python DRC checks...")
    violations = []
    rdb = rdb_mod.ReportDatabase("DRC")
    rdb_cell = rdb.create_cell(top_cells[0] if top_cells else "soc_top")
    rdb_cat_width = rdb.create_category("min_width")
    rdb_cat_space = rdb.create_category("min_spacing")
    rdb_cat_area  = rdb.create_category("min_area")

    # Sky130 DRC rules (key subset)
    # Source: Sky130 PDK DRC manual
    DRC_RULES = {
        # (layer_name, gds_layer, gds_dtype): (min_width_um, min_space_um, min_area_um2)
        "met1": (0.14, 0.14, 0.083),
        "met2": (0.14, 0.14, 0.0676),
        "met3": (0.30, 0.30, 0.240),
        "met4": (0.30, 0.30, 0.240),
        "met5": (1.60, 1.60, 4.000),
        "poly":  (0.15, 0.21, 0.0),
        "diff":  (0.15, 0.27, 0.0),
        "nwell": (0.84, 1.27, 0.0),
    }

    # Sky130A layer number map
    LAYER_MAP = {
        "diff":  (65, 20), "tap":   (65, 44),
        "nwell": (64, 20), "poly":  (66, 20),
        "met1":  (67, 20), "via":   (68, 20),
        "met2":  (69, 20), "via2":  (70, 20),
        "met3":  (71, 20), "via3":  (72, 20),
        "met4":  (73, 20), "via4":  (76, 20),
        "met5":  (77, 20),
    }

    total_violations = 0
    for layer_name, (lnum, ldtype) in LAYER_MAP.items():
        if layer_name not in DRC_RULES:
            continue
        min_w, min_s, min_a = DRC_RULES[layer_name]
        layer_idx = layout.find_layer(lnum, ldtype)
        if layer_idx is None:
            continue

        region = db.Region(layout.top_cells()[0].begin_shapes_rec(layer_idx))

        # Min width check
        width_viol = region.width_check(min_w * 1000 / layout.dbu)
        w_count = width_viol.count()
        if w_count > 0:
            cat = rdb.create_category(rdb_cat_width, layer_name)
            for item in width_viol.each():
                rdb.create_item(rdb_cell.rdb_id(), cat.rdb_id(), db.CplxTrans(layout.dbu), item)
            total_violations += w_count
            violations.append(f"  {layer_name} min_width violations : {w_count}")

        # Min spacing check
        space_viol = region.space_check(min_s * 1000 / layout.dbu)
        s_count = space_viol.count()
        if s_count > 0:
            cat = rdb.create_category(rdb_cat_space, layer_name)
            for item in space_viol.each():
                rdb.create_item(rdb_cell.rdb_id(), cat.rdb_id(), db.CplxTrans(layout.dbu), item)
            total_violations += s_count
            violations.append(f"  {layer_name} min_spacing violations: {s_count}")

    # Write report
    rdb.save(str(rpt_path))

    print(f"\n=== DRC Summary ===")
    print(f"  Total violations: {total_violations}")
    if violations:
        for v in violations:
            print(v)
    else:
        print("  No violations found in checked layers")

def summarize_report(rpt_path):
    """Parse KLayout XML DRC report and print summary."""
    import xml.etree.ElementTree as ET
    try:
        tree = ET.parse(str(rpt_path))
        root = tree.getroot()
        total = 0
        cats = {}
        for item in root.iter("item"):
            cat = item.find("../name")
            cat_name = cat.text if cat is not None else "unknown"
            cats[cat_name] = cats.get(cat_name, 0) + 1
            total += 1
        print(f"\n=== DRC Result ===")
        print(f"  Total violations: {total}")
        for cat, cnt in sorted(cats.items(), key=lambda x: -x[1])[:20]:
            print(f"  {cnt:6d}  {cat}")
        if total == 0:
            print("  DRC CLEAN")
    except Exception as e:
        print(f"  Could not parse report: {e}")

def find_klayout_exe():
    """Find KLayout executable on system."""
    import shutil
    for name in ["klayout", "klayout.exe"]:
        path = shutil.which(name)
        if path:
            return path
    for p in [
        "/c/Program Files/KLayout/klayout.exe",
        "/c/Users/chaising/AppData/Local/Programs/KLayout/klayout.exe",
    ]:
        if os.path.exists(p):
            return p
    return None

def check_deck_only(deck_path):
    """Verify DRC deck exists and show basic info."""
    if deck_path.exists():
        size = deck_path.stat().st_size
        print(f"\nDRC deck found: {deck_path.name} ({size/1024:.0f} KB)")
    else:
        print(f"\nDRC deck not found: {deck_path}")

def write_placeholder_report(rpt_path, gds_path, deck_path):
    """Write placeholder report when GDS is not available."""
    RPT_DIR.mkdir(parents=True, exist_ok=True)
    txt_rpt = rpt_path.with_suffix(".rpt")
    txt_rpt.write_text(
        f"DRC REPORT — soc_top\n"
        f"Status : PENDING — GDS not yet generated\n"
        f"GDS    : {gds_path}\n"
        f"Deck   : {deck_path}\n\n"
        f"Requires: Run make route && make gds first to generate GDSII.\n"
        f"Then re-run: py -3.11 physical_verification/klayout/run_drc_sky130.py\n"
    )
    print(f"Placeholder report: {txt_rpt}")

if __name__ == "__main__":
    main()
