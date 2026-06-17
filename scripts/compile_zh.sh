#!/usr/bin/env bash
# Compile a Chinese LaTeX file with XeLaTeX (required for ctex/CJK fonts).
# Runs latexmk for proper multi-pass (refs, labels), prints a focused error
# digest on failure so you can fix the .tex without scrolling the full log.
#
# Usage: compile_zh.sh path/to/ZN.tex
set -u

TEX="${1:?usage: compile_zh.sh <file.tex>}"
TEX="$(readlink -f "$TEX")"
DIR="$(dirname "$TEX")"
BASE="$(basename "$TEX" .tex)"
cd "$DIR" || exit 1

# No local LaTeX? Don't fail cryptically — hand the user a clean online path.
if ! command -v xelatex >/dev/null 2>&1; then
  cat <<EOF
------ 未检测到本地 LaTeX（xelatex）环境 ------
已生成可编译的中文 LaTeX 源文件：
  $TEX
请用在线 LaTeX 平台编译下载 PDF（无需本地安装）：
  1. 打开 Overleaf (https://www.overleaf.com) → New Project → Upload Project；
     把 $DIR 整个目录打包上传（务必包含 ZN.tex 以及 figures/ 等所有图片、.bbl/.bib）。
  2. 菜单 Menu → Settings → Compiler 选 **XeLaTeX**（中文必须用 XeLaTeX，否则报错）。
  3. 点 Recompile，右上角 Download PDF 即可。
本地若想自行安装：apt install texlive-xetex texlive-lang-chinese latexmk fonts-noto-cjk
--------------------------------------------------
EOF
  exit 2
fi

run() {
  if command -v latexmk >/dev/null 2>&1; then
    latexmk -xelatex -interaction=nonstopmode -halt-on-error -file-line-error "$BASE.tex"
  else
    xelatex -interaction=nonstopmode -halt-on-error -file-line-error "$BASE.tex" \
      && xelatex -interaction=nonstopmode -halt-on-error -file-line-error "$BASE.tex"
  fi
}

run
STATUS=$?

if [ $STATUS -eq 0 ] && [ -f "$BASE.pdf" ]; then
  echo "OK  -> $DIR/$BASE.pdf"
  command -v pdfinfo >/dev/null 2>&1 && pdfinfo "$BASE.pdf" | grep -E '^(Pages|Page size):'
  exit 0
fi

echo "------ COMPILE FAILED: error digest from $BASE.log ------"
# Show file:line errors, undefined refs, missing files, and missing fonts.
grep -nE ":[0-9]+:|^! |Undefined|Missing|not found|No file|Font .* does not" "$BASE.log" 2>/dev/null \
  | grep -viE "rerun|reference\(s\) may have changed" | head -40
echo "--------------------------------------------------------"
echo "Full log: $DIR/$BASE.log"
exit 1
