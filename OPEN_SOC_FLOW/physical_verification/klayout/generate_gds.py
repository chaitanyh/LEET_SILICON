#!/usr/bin/env python3
"""
generate_gds.py — Generate GDSII from routed DEF using KLayout Python API.

Full LEF+DEF → GDS requires one of:
  a) OpenROAD write_gds (not in PI 2024-12-14 binary)
  b) KLayout 0.28+ with full application context (0.26 on Ubuntu 22.04 apt crashes)
  c) Magic VLSI

This script uses pip-installed klayout (db module only, no CLI/pya) to write
a structured placeholder GDS containing:
  - Die outline (met1 layer, actual die dimensions from DEF)
  - Core boundary (met2 layer)
  - Standard cell count annotation
  - Chip label text

The routed.def and routed.v are the primary deliverables. GDS with full
geometry requires a newer OpenROAD build or ORFS.

Usage:
  python3 physical_verification/klayout/generate_gds.py \
      --def physical/routed.def --gds gds/soc_top.gds
"""
import sys, os, argparse, re
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
PDK_VER = "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"

def _default_pdk_root():
    if "PDK_ROOT" in os.environ:
        return Path(os.environ["PDK_ROOT"]) / "sky130A"
    home = Path(os.environ.get("USERPROFILE", os.environ.get("HOME", str(Path.home()))))
    return home / ".volare/volare/sky130/versions" / PDK_VER / "sky130A"

def parse_def_dimensions(def_path):
    """Extract die area and unit scale from DEF DIEAREA."""
    die = None
    units = 1000  # default sky130 DEF units = 1000 per micron
    try:
        with open(def_path, "r") as f:
            for line in f:
                if line.startswith("UNITS DISTANCE MICRONS"):
                    units = int(line.split()[-1].rstrip(";"))
                if line.startswith("DIEAREA"):
                    nums = re.findall(r"\d+", line)
                    if len(nums) >= 4:
                        die = (int(nums[0]), int(nums[1]), int(nums[2]), int(nums[3]))
                        break
    except Exception:
        pass
    return die, units

def count_def_cells(def_path):
    """Count placed cells from DEF COMPONENTS section."""
    count = 0
    try:
        with open(def_path, "r") as f:
            in_comp = False
            for line in f:
                if line.startswith("COMPONENTS"):
                    m = re.search(r"COMPONENTS\s+(\d+)", line)
                    if m:
                        count = int(m.group(1))
                    break
    except Exception:
        pass
    return count

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--def",     dest="def_file",  default=None)
    parser.add_argument("--lef",     dest="lef_file",  default=None)
    parser.add_argument("--techlef", dest="tech_lef",  default=None)
    parser.add_argument("--gds",     dest="gds_file",  default=None)
    args = parser.parse_args()

    ROUTED_DEF = Path(args.def_file)  if args.def_file else PROJECT_ROOT / "physical/routed.def"
    OUTPUT_GDS = Path(args.gds_file) if args.gds_file else PROJECT_ROOT / "gds/soc_top.gds"
    OUTPUT_GDS.parent.mkdir(parents=True, exist_ok=True)

    print("=" * 65)
    print("  GDS Generation — soc_top")
    print(f"  DEF  : {ROUTED_DEF}")
    print(f"  Out  : {OUTPUT_GDS}")
    print("=" * 65)

    try:
        import klayout.db as db
        print(f"  KLayout: {db.__version__}")
    except ImportError:
        print("ERROR: klayout Python package not installed.")
        sys.exit(1)

    # Parse DEF for actual die dimensions
    die_coords = None
    cell_count = 0
    if ROUTED_DEF.exists():
        die_coords, units = parse_def_dimensions(ROUTED_DEF)
        cell_count = count_def_cells(ROUTED_DEF)
        print(f"  DEF parsed: {cell_count} components, units={units}")
        if die_coords:
            w = (die_coords[2] - die_coords[0]) / units
            h = (die_coords[3] - die_coords[1]) / units
            print(f"  Die area: {w:.0f} x {h:.0f} µm")
    else:
        print(f"  WARNING: DEF not found — using default 1400x1400 µm")
        units = 1000

    # Build structured GDS with die outline
    # sky130 GDS unit: 1 db unit = 1 nm = 0.001 µm
    layout = db.Layout()
    layout.dbu = 0.001  # 1 nm

    top_cell = layout.create_cell("soc_top")

    # Die outline on met1 (layer 67/20)
    if die_coords:
        # DEF coords are in DEF units → convert to nm
        nm_per_def = 1000 / units  # sky130: units=1000, so 1 DEF unit = 1 nm
        x0 = int(die_coords[0] * nm_per_def)
        y0 = int(die_coords[1] * nm_per_def)
        x1 = int(die_coords[2] * nm_per_def)
        y1 = int(die_coords[3] * nm_per_def)
    else:
        x0, y0, x1, y1 = 0, 0, 1400000, 1400000  # 1400 µm default

    met1 = layout.layer(67, 20)
    top_cell.shapes(met1).insert(db.Box(x0, y0, x1, y1))

    # Core boundary on met2 (layer 68/20) — inset 40 µm = 40000 nm
    boundary = 40000
    met2 = layout.layer(68, 20)
    top_cell.shapes(met2).insert(db.Box(
        x0 + boundary, y0 + boundary, x1 - boundary, y1 - boundary
    ))

    # Chip label on text layer (83/44)
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    text_layer = layout.layer(83, 44)
    top_cell.shapes(text_layer).insert(
        db.Text("soc_top", db.Trans(db.Vector(cx, cy)))
    )
    top_cell.shapes(text_layer).insert(
        db.Text(f"{cell_count} cells", db.Trans(db.Vector(cx, cy - 50000)))
    )

    layout.write(str(OUTPUT_GDS))
    size_kb = OUTPUT_GDS.stat().st_size / 1e3
    print(f"\nGDS written: {OUTPUT_GDS.name} ({size_kb:.1f} kB)")
    print(f"  Die outline + core boundary from routed DEF")
    print(f"  Cell count: {cell_count}")
    print()
    print("NOTE: Full merged GDS (with std-cell geometry) requires:")
    print("  - OpenROAD write_gds (not in PI 2024-12-14 binary)")
    print("  - Or: KLayout 0.28+ with ORFS tech bundle")
    print("  - Or: Magic VLSI stream-out")
    print(f"\nGDS COMPLETE (structural outline): {OUTPUT_GDS}")

if __name__ == "__main__":
    main()
