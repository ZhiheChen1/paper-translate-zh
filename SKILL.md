---
name: paper-translate-zh
description: >-
  Translate an academic paper into a polished, academically-styled Chinese PDF.
  Use this skill whenever the user wants to 翻译论文 / 把论文翻成中文 / translate a
  paper, manuscript, preprint, or any scholarly work into Chinese, produce a
  Chinese version (ZN.pdf / 中文版), or read a foreign-language paper in Chinese.
  Trigger even when the user only drops a paper PDF, gives an arXiv link/ID, or
  says "翻译一下" / "做个中文版" / "translate this to Chinese" without naming LaTeX.
  Two source paths: if LaTeX source is available (arXiv e-print, or user-provided
  .tex) translate the source directly (highest fidelity); otherwise extract
  text+figures from the PDF. Output a Chinese ZN.tex and compile to ZN.pdf with
  XeLaTeX — or, when no local LaTeX is installed, hand the user ZN.tex with
  online-compile (Overleaf) instructions. Do NOT use for non-academic documents
  (contracts, slides, web pages) or for a side-by-side bilingual reader.
---

# Paper → 中文 PDF 翻译

把一篇外文学术论文翻成**学术化中文**，产出可直接阅读、带引用超链接的 `ZN.pdf`。
译文质量是这个 skill 的全部价值——排版只是载体，**译得地道、准确、像中文母语学者写的论文**才是目标。

> **跨工具说明**：本 skill 适用于任何支持 Skill 规范的 CLI / 智能体工具（Claude Code、Codex、
> Copilot CLI、Gemini CLI 等）。下文命令里写的 `~/.claude/skills/paper-translate-zh/` 是
> Claude Code 的默认安装路径；在其他工具下，请替换为本 skill 的**实际安装目录**（含本 `SKILL.md` 的目录）。

## 第 0 步：选择翻译路径（决定成败）

先判断**有没有 LaTeX 源码**，两条路径保真度差别巨大：

| 情形 | 路径 | 为什么 |
| --- | --- | --- |
| arXiv 论文（有 id/链接），或用户直接给了 `.tex` 源码 | **路径 A：源码直译**（首选） | 公式、图、表、参考文献、交叉引用都已在源码里且正确，**只需重写正文文字**，无须从图里逐符号转写公式，保真度最高 |
| 只有 PDF（无源码、扫描件、出版社 PDF） | **路径 B：PDF 提取** | 退而求其次，从 PDF 抽文字+图，公式与表格需要重排 |

拿到 arXiv 链接/编号要**优先试路径 A**；只有当 e-print 无源码（PDF-only）时才退回路径 B。

---

## 路径 A：LaTeX 源码直译（首选）

### A1. 取得源码

- **arXiv**：用脚本下载并解包 e-print，它会列出 `.tex` 文件、标出主文件、列出已有图片：
  ```bash
  bash ~/.claude/skills/paper-translate-zh/scripts/fetch_arxiv_source.sh "<arxiv-id或链接>" "<workdir>"
  ```
  输出里的 `MAIN_TEX=...` 就是主文件（含 `\documentclass` 与 `\begin{document}`）。
- **用户自带源码**：直接用其主 `.tex` 与配套图片、`.bib`/`.bbl`。

### A2. 注入中文支持

复制主文件为 `ZN.tex`，在 `\documentclass{...}` 之后**紧接着**插入（XeLaTeX + 系统中文字体，
对各种文档类兼容性最好）：
```latex
\usepackage{xeCJK}
\setCJKmainfont{Noto Serif CJK SC}
\setCJKsansfont{Noto Sans CJK SC}
```
若系统无 Noto CJK，可换 `SimSun`/`Source Han Serif SC` 等任一已装中文字体。
**用 Edit/Write 工具改写文件，不要用 `sed`/正则替换**（反斜杠极易被转义破坏）。

### A3. 原地翻译

逐段把**正文文字**改写成学术化中文（语体要求见下方[通用章节](#学术化中文两条路径通用)），同时**原样保留**：
- 所有数学环境与公式（`$...$`、`equation`、`align` 等）——一个符号都不动；
- `\includegraphics`、`figure`/`table` 结构、`\label`/`\ref`/`\cite`/`\eqref` 等命令；
- 文献部分（`thebibliography` 或 `\bibliography{...}`）——**不译**。

只翻译：标题、摘要、关键词、正文段落、章节标题、**图注/表注里的说明文字**（`\caption{...}` 内）、脚注、致谢。

### A4. 处理文献与编译附属文件

- 若源码目录里有 `<主文件名>.bbl`（arXiv 通常自带），把它**复制为 `ZN.bbl`**，否则正文引用会显示未定义：
  ```bash
  cp "<workdir>/source/<main>.bbl" "<workdir>/source/ZN.bbl"   # 有 .bbl 时
  ```
- 保持 `ZN.tex` 与图片、`.bbl`/`.bib`、自定义 `.sty`/`.cls` **在同一目录**编译。
- 引用超链接：若原文未加载 hyperref，可在导言区补 `\usepackage{hyperref}`（放在 natbib 之后），
  正文 `\cite` 即变为可点击链接；原文已用则无须改动。

然后直接跳到 [编译](#编译znpdf含无-latex-环境)。

---

## 路径 B：从 PDF 提取翻译

> **依赖 `pdf` skill**：本步骤建立在官方 `pdf` skill 之上；`extract_pdf.py` 是与之同一套工具链
> （pdfplumber / pypdf / poppler）的便捷封装。扫描件需 OCR、加密 PDF、表单等，先用 `pdf` skill
> 处理（如 OCR 成可搜索 PDF）再回来翻译。

### B1. 提取：文字 + 图片到工作目录

```bash
python3 ~/.claude/skills/paper-translate-zh/scripts/extract_pdf.py "<源.pdf>" "<workdir>"
```
产物：
- `full_text.txt` —— 全文文字，带 `==== PAGE n ====` 标记。**翻译的主要文本来源。**
- `pages/page_NN.png` —— 每页整页渲染图。**务必用 Read 工具看这些图**：纯文字抽取会丢两栏顺序、
  公式、上下标、图表位置——看页面图才能还原真实结构、准确转写公式、定位图注。
- `figures/p{n}_fig{k}.png` —— 自动裁出的图片，用于嵌入。
- `manifest.json` —— 页数与图片清单。

自动裁图不是万能的：矢量图、被切块的图、没框准的图，从 `pages/page_NN.png` 里按需手动重裁。
**判断哪些是正文该保留的真图**（架构图、结果图、示意图），丢弃 logo、公式截块、装饰线。

### B2. 翻译：写 ZN.tex

以 `assets/ZN_template.tex` 为骨架（ctex 单栏、中文图表标题、引用超链接齐备），复制到工作目录改写：
```bash
cp ~/.claude/skills/paper-translate-zh/assets/ZN_template.tex "<workdir>/ZN.tex"
```
路径 B 的特有处理：
- **公式**用 LaTeX **重排**（非截图），从 `pages/` 页面图逐符号转写（上下标、希腊字母、求和/积分上下限最易错）。
- **表格**重排为 LaTeX **中文三线表**（`booktabs`），表头/表注译中文、数据照搬；极复杂无法重排时才退而嵌入页面裁图。
- **图**用 `\includegraphics` 嵌入 `figures/` 里的图，`[H]` 就近放置、顺序同原文；图内坐标轴/图例标签保留原文。
- **参考文献**用 `thebibliography` + `\bibitem{refN}`，正文 `\cite{refN}`；hyperref 自动把 `[n]` 变成可点击链接。文献条目**保留原文不翻译**。
- 图/表/公式/章节交叉引用用 `\cref{label}`（→"图 1""式 3"），模板已配好中文名与 `colorlinks`。

---

## 学术化中文（两条路径通用）

不是逐字直译，而是**用中文学术语体重写**。判断标准：一位该领域的中文学者读起来，觉得这就是
中文写就的论文，而非"翻译腔"。

- **意译优先于字面**。先读懂整句论证，再用通顺中文表达。英文长句拆成符合中文节奏的短句；
  被动多改主动（"It is observed that…" → "实验表明……"）。
- **术语：中文为主，首次出现括注英文全称与缩写**，如"卷积神经网络（Convolutional Neural
  Network, CNN）"；此后用中文或公认缩写。译名取学界通用译法，拿不准时保留英文原词而非生造；
  GPU、BERT、Transformer 等约定俗成的直接用原词。
- **学术语体**：用"本文""该方法""如式(3)所示""综上所述""值得注意的是"等；避免口语与机翻僵硬句式。
- **数字与单位**：阿拉伯数字保留；单位规范（ms、GFLOPs）；百分数、区间照原文。
- **忠实**：不增删原意、不漏译、不臆造数据。看不懂的句子对照原文（路径 A 看源码、路径 B 看 `pages/` 页面图）再译，绝不跳过或编造。
- **专有名词**：人名、机构名、数据集名（ImageNet、COCO）、方法缩写一般保留原文。

---

## 编译：ZN.pdf（含无 LaTeX 环境）

```bash
bash ~/.claude/skills/paper-translate-zh/scripts/compile_zh.sh "<workdir>/ZN.tex"
```

脚本用 `latexmk -xelatex`（中文必须 XeLaTeX）。两种结果：

- **有本地 LaTeX** → 直接产出 `ZN.pdf`；失败时打印精简错误摘要（file:line、未定义引用、缺图、缺字体）。常见问题：
  - 缺图：`\includegraphics` 路径要相对 `ZN.tex`（模板已设 `\graphicspath`）。
  - 引用未定义：路径 A 记得把 `<main>.bbl` 复制成 `ZN.bbl`；或重跑一次让 latexmk 解析。
  - 特殊字符：正文 `% & _ # $ ^ ~ \` 需转义或放进数学环境。
  - 图太大溢出：`\includegraphics[width=0.8\linewidth]{...}` 限宽。
- **无本地 LaTeX**（脚本检测到 `xelatex` 缺失）→ 不报错，而是打印**在线编译指引**并保留 `ZN.tex`。
  此时按脚本提示转达用户：把工作目录（含 `ZN.tex` + 所有图片 + `.bbl`/`.bib`）打包上传到
  [Overleaf](https://www.overleaf.com)，**编译器选 XeLaTeX**，Recompile 后 Download PDF。
  为方便用户上传，可帮其打包：`cd <workdir> && zip -r ZN_overleaf.zip .`（排除多余的 `pages/` 中间产物）。

修好 `ZN.tex` 后重新编译，直到 `OK -> .../ZN.pdf`。

## 交付

- 有 PDF：报告 `ZN.pdf` 路径与页数。
- 无本地 LaTeX：交付 `ZN.tex`（及打包好的 zip）+ 一句话的 Overleaf 编译步骤。

简述完成度（走的哪条路径 / 全文翻译 / 含 N 图 M 表），并**诚实说明**任何未完美处理之处
（如某矢量图以页面裁图代替、某复杂表保留为图、e-print 无源码而改走 PDF）。不要谎报已完成。

## 长论文提示

文章很长时，分章节翻译写入 `ZN.tex`，每完成几节先试编译一次尽早暴露 LaTeX 错误，
而不是写完整篇才第一次编译。路径 A 尤其要先编译一次原始源码（仅注入中文、未翻译前），
确认本机能跑通该论文的文档类与宏包，再开始翻译。
