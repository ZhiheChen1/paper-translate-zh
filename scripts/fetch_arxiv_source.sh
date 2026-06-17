#!/usr/bin/env bash
# Download and unpack an arXiv paper's LaTeX source (e-print), then point out
# the main .tex. Translating the real source beats PDF extraction: equations,
# figures, tables, citations and cross-refs are already correct — you only
# rewrite the prose.
#
# Usage: fetch_arxiv_source.sh <arxiv-id-or-url> <outdir>
#   e.g. fetch_arxiv_source.sh 1708.02002 work
#        fetch_arxiv_source.sh https://arxiv.org/abs/2305.12345 work
set -u

RAW="${1:?usage: fetch_arxiv_source.sh <arxiv-id-or-url> <outdir>}"
OUT="${2:?usage: fetch_arxiv_source.sh <arxiv-id-or-url> <outdir>}"

# Normalise to a bare id: strip URL, /abs/, /pdf, version is kept if given.
ID="$(printf '%s' "$RAW" | sed -E 's#.*arxiv\.org/(abs|pdf|e-print)/##; s#\.pdf$##; s#/$##')"
mkdir -p "$OUT"
TARBALL="$OUT/_arxiv_src"

echo "Fetching arXiv source for: $ID"
# arXiv asks for a descriptive User-Agent; -L follows redirects.
if ! curl -fsL -A "paper-translate-zh/1.0 (LaTeX source fetch)" \
     "https://arxiv.org/e-print/$ID" -o "$TARBALL"; then
  echo "ERROR: download failed. Check the id, or the paper may have no source"
  echo "       (some arXiv entries are PDF-only — fall back to the PDF pipeline)."
  exit 1
fi

SRC="$OUT/source"
rm -rf "$SRC"; mkdir -p "$SRC"
# e-print may be: a gzipped tar, a single gzipped file, or rarely a bare file.
if tar tzf "$TARBALL" >/dev/null 2>&1; then
  tar xzf "$TARBALL" -C "$SRC"
elif gzip -t "$TARBALL" >/dev/null 2>&1; then
  gunzip -c "$TARBALL" > "$SRC/main.tex"   # single-file source -> a .tex
else
  echo "ERROR: unrecognised e-print format (maybe PDF-only). Use the PDF pipeline."
  exit 1
fi
rm -f "$TARBALL"

echo "Unpacked to: $SRC"
echo "--- .tex files ---"
find "$SRC" -maxdepth 3 -iname '*.tex' | sort
echo "--- likely main .tex (has \\documentclass + \\begin{document}) ---"
MAIN=""
while IFS= read -r f; do
  if grep -lqE '\\documentclass' "$f" 2>/dev/null && grep -lq '\\begin{document}' "$f" 2>/dev/null; then
    echo "  $f"; [ -z "$MAIN" ] && MAIN="$f"
  fi
done < <(find "$SRC" -iname '*.tex' | sort)
echo "--- figures present (already usable, no re-extraction needed) ---"
find "$SRC" -maxdepth 3 -iregex '.*\.\(pdf\|png\|jpg\|jpeg\|eps\)$' | sort | head -40
[ -n "$MAIN" ] && echo "MAIN_TEX=$MAIN"
