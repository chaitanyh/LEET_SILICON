#!/usr/bin/env python3
"""
generate_gds.py — Generate GDSII from routed DEF using KLayout Python API.
Merges: std-cell GDS (from PDK) + routed DEF placement → final GDS.

Usage: py -3.11 physical_verification/klayout/generate_gds.py [options]
       python3 physical_verification/klayout/generate_gds.py --def physical/routed.def --lef ... --gds gds/soc_top.gds
"""
import sys, os, argparse
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
PDK_VER = "bdc9412b3e468c102d01b7cf6337be06ec6e9c9a"

def _default_pdk_root():
    # Prefer PDK_ROOT env var (set by CI), fall back to volare default
    if "PDK_ROOT" in os.environ:
        return Path(os.environ["PDK_ROOT"]) / "sky130A"
    home = Path(os.environ.get("USERPROFILE", os.environ.get("HOME", str(Path.home()))))
    return home / ".volare/volare/sky130/versions" / PDK_VER / "sky130A"

def main():
    parser = argparse.ArgumentParser(description="Generate GDS from routed DEF")
    parser.add_argument("--def",     dest="def_file", default=None, help="Routed DEF file")
    parser.add_argument("--lef",     dest="lef_file", default=None, help="Cell LEF file")
    parser.add_argument("--techlef", dest="tech_lef", default=None, help="Tech LEF file")
    parser.add_argument("--gds",     dest="gds_file", default=None, help="Output GDS file")
    args = parser.parse_args()

    PDK_ROOT = _default_pdk_root()

    ROUTED_DEF   = Path(args.def_file)  if args.def_file else PROJECT_ROOT / "physical/routed.def"
    TECH_LEF     = Path(args.tech_lef) if args.tech_lef else PDK_ROOT / "libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"
    CELL_LEF     = Path(args.lef_file) if args.lef_file else PDK_ROOT / "libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
    STD_CELL_GDS = PDK_ROOT / "libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds"
    OUTPUT_GDS   = Path(args.gds_file) if args.gds_file else PROJECT_ROOT / "gds/soc_top.gds"
    OUTPUT_GDS.parent.mkdir(parents=True, exist_ok=True)
    print("=" * 65)
    print("  GDS Generation — soc_top")
    print(f"  DEF  : {ROUTED_DEF}")
    print(f"  PDK  : sky130_fd_sc_hd")
    print(f"  Out  : {OUTPUT_GDS}")
    print("=" * 65)

    try:
        import klayout.db as db
        print(f"  KLayout: {db.__version__}")
    except ImportError:
        print("ERROR: klayout not installed.")
        sys.exit(1)

    if not ROUTED_DEF.exists():
        print(f"\nWARNING: Routed DEF not found: {ROUTED_DEF}")
        print("  GDS generation requires a routed DEF from OpenROAD.")
        print("  Run: openroad -exit openroad/routing/routing.tcl first.")
        print()
        print("  Creating placeholder GDS for flow testing...")
        create_placeholder_gds(OUTPUT_GDS)
        return

    # Load std-cell GDS
    print(f"\nLoading std-cell GDS: {STD_CELL_GDS} ...", flush=True)
    layout = db.Layout()
    if STD_CELL_GDS.exists():
        layout.read(str(STD_CELL_GDS))
        print(f"  Loaded {layout.cells()} std-cells")
    else:
        print(f"  WARNING: std-cell GDS not found: {STD_CELL_GDS}")

    # Read DEF into layout
    print(f"Reading DEF: {ROUTED_DEF} ...", flush=True)
    lef_defs = db.LEFDEFReaderOptions()
    lef_defs.read_lef_with_layout = True

    try:
        # Read LEF files for technology
        layout_def = db.Layout()
        reader = db.Reader(lef_defs)
        reader.read(str(TECH_LEF), layout_def)
        reader.read(str(CELL_LEF), layout_def)
        reader.read(str(ROUTED_DEF), layout_def)
        print(f"  DEF loaded: {layout_def.cells()} cells")

        # Merge std-cell GDS into DEF layout
        for cell in layout.each_cell():
            # Only import if not already present
            if layout_def.cell(cell.name) is None:
                layout_def.copy_cell(cell)

        # Write GDS
        print(f"\nWriting GDS: {OUTPUT_GDS} ...", flush=True)
        layout_def.write(str(OUTPUT_GDS))
        size_mb = OUTPUT_GDS.stat().st_size / 1e6
        print(f"  Written: {OUTPUT_GDS.name} ({size_mb:.1f} MB)")
        print(f"\nGDS COMPLETE: {OUTPUT_GDS}")

    except Exception as e:
        print(f"ERROR: {e}")
        print("Creating placeholder GDS...")
        create_placeholder_gds(OUTPUT_GDS)

def create_placeholder_gds(OUTPUT_GDS):
    """Create a minimal placeholder GDS to demonstrate the flow."""
    try:
        import klayout.db as db
        layout = db.Layout()
        layout.dbu = 0.001  # 1 nm = 0.001 µm database unit
        top_cell = layout.create_cell("soc_top")

        # Get or create met1 layer (sky130 layer 67/20)
        layer = layout.layer(67, 20)

        # Create a bounding box representing the chip footprint
        # 1180 µm × 1180 µm (in database units = nm)
        box = db.Box(0, 0, 1180000, 1180000)  # 1180 × 1180 µm in nm
        top_cell.shapes(layer).insert(box)

        # Add text label
        layer_text = layout.layer(83, 44)  # text layer
        text = db.Text("soc_top", db.Trans(db.Vector(590000, 590000)))
        top_cell.shapes(layer_text).insert(text)

        layout.write(str(OUTPUT_GDS))
        print(f"Placeholder GDS: {OUTPUT_GDS} (chip outline only)")
        print("  NOTE: Full GDS requires routed DEF from OpenROAD")

    except Exception as e:
        print(f"Could not create placeholder GDS: {e}")

if __name__ == "__main__":
    main()
