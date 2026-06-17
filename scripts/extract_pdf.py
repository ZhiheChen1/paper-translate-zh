#!/usr/bin/env python3
"""Extract a paper PDF into a working directory for translation.

Produces, under <outdir>:
  full_text.txt        all page text, with `==== PAGE n ====` markers
  text/page_NN.txt     per-page text (1-based, zero-padded)
  pages/page_NN.png    full-page render (for reading layout, captions, equations)
  figures/p{n}_fig{k}.png  cropped figure regions (raster images on each page)
  manifest.json        page count + figure list (page, index, bbox, pixel size)

Why both page renders and figure crops: figure crops give clean, embeddable
images for the common case (raster figures); page renders are the reliable
fallback you can view to read the layout, locate captions, transcribe
equations, and crop anything the automatic pass missed.

Usage:
  python3 extract_pdf.py <input.pdf> <outdir> [--dpi 200] [--min-fig-px 120]
"""
import argparse, json, os, subprocess, sys
from pathlib import Path


def render_pages(pdf, pages_dir, dpi):
    """Render every page to PNG with poppler's pdftoppm (most reliable renderer)."""
    pages_dir.mkdir(parents=True, exist_ok=True)
    prefix = pages_dir / "page"
    subprocess.run(
        ["pdftoppm", "-png", "-r", str(dpi), str(pdf), str(prefix)],
        check=True,
    )
    # pdftoppm writes page-1.png, page-2.png ... -> normalise to page_01.png
    out = {}
    for p in sorted(pages_dir.glob("page-*.png")):
        n = int(p.stem.split("-")[-1])
        new = pages_dir / f"page_{n:02d}.png"
        p.rename(new)
        out[n] = new
    return out


def crop_figures(pdf, page_pngs, figures_dir, dpi, min_px):
    """Crop raster-image regions from each rendered page using pdfplumber bboxes."""
    import pdfplumber
    from PIL import Image

    figures_dir.mkdir(parents=True, exist_ok=True)
    scale = dpi / 72.0  # PDF points -> rendered pixels
    figures = []
    with pdfplumber.open(str(pdf)) as doc:
        for pidx, page in enumerate(doc.pages, start=1):
            png = page_pngs.get(pidx)
            if png is None:
                continue
            try:
                sheet = Image.open(png)
            except Exception:
                continue
            for k, im in enumerate(page.images, start=1):
                x0, x1 = im["x0"] * scale, im["x1"] * scale
                # pdfplumber 'top' is from page top already
                top, bottom = im["top"] * scale, im["bottom"] * scale
                w, h = int(x1 - x0), int(bottom - top)
                if w < min_px or h < min_px:
                    continue  # skip logos, inline math, rules, bullets
                box = (max(0, int(x0)), max(0, int(top)),
                       min(sheet.width, int(x1)), min(sheet.height, int(bottom)))
                name = f"p{pidx:02d}_fig{k}.png"
                try:
                    sheet.crop(box).save(figures_dir / name)
                except Exception:
                    continue
                figures.append({"page": pidx, "index": k, "file": f"figures/{name}",
                                "width_px": w, "height_px": h})
    return figures


def extract_text(pdf, text_dir, full_txt):
    import pdfplumber
    text_dir.mkdir(parents=True, exist_ok=True)
    parts = []
    with pdfplumber.open(str(pdf)) as doc:
        for pidx, page in enumerate(doc.pages, start=1):
            try:
                t = page.extract_text() or ""
            except Exception:
                t = ""
            (text_dir / f"page_{pidx:02d}.txt").write_text(t, encoding="utf-8")
            parts.append(f"==== PAGE {pidx} ====\n{t}\n")
    full_txt.write_text("\n".join(parts), encoding="utf-8")
    return len(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("outdir")
    ap.add_argument("--dpi", type=int, default=200)
    ap.add_argument("--min-fig-px", type=int, default=120)
    a = ap.parse_args()

    pdf = Path(a.pdf).expanduser().resolve()
    out = Path(a.outdir).expanduser().resolve()
    if not pdf.exists():
        sys.exit(f"ERROR: PDF not found: {pdf}")
    out.mkdir(parents=True, exist_ok=True)

    n = extract_text(pdf, out / "text", out / "full_text.txt")
    page_pngs = render_pages(pdf, out / "pages", a.dpi)
    figures = crop_figures(pdf, page_pngs, out / "figures", a.dpi, a.min_fig_px)

    manifest = {"pdf": str(pdf), "pages": n, "dpi": a.dpi,
                "figures": figures, "n_figures": len(figures)}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False),
                                       encoding="utf-8")
    print(f"Extracted {n} pages, {len(figures)} figure crops -> {out}")
    print(f"  text:    {out/'full_text.txt'}")
    print(f"  pages:   {out/'pages'}  (view these to read layout/equations/captions)")
    print(f"  figures: {out/'figures'}")


if __name__ == "__main__":
    main()
