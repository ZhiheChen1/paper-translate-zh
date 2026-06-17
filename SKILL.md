---
name: paper-translate-zh
description: >-
  Translate an academic paper PDF into a polished, academically-styled Chinese
  PDF. Use this skill whenever the user wants to 翻译论文 / 把论文翻成中文 /
  translate a paper, manuscript, preprint, or any scholarly .pdf into Chinese,
  produce a Chinese version (ZN.pdf / 中文版) of a paper, or read a foreign-language
  paper in Chinese. Trigger even when the user only drops a paper PDF and says
  "翻译一下" / "做个中文版" / "translate this to Chinese" without naming LaTeX or PDF
  output. Pipeline: extract text+figures with the pdf tooling, write a Chinese
  ZN.tex, compile to ZN.pdf with XeLaTeX. Do NOT use for non-academic documents
  (contracts, slides, web pages) or when the user wants a side-by-side bilingual
  reader rather than a clean Chinese-only paper.
---

# Paper → 中文 PDF 翻译

把一篇外文学术论文 PDF 翻成**学术化中文**，产出可直接阅读的 `ZN.pdf`。
译文质量是这个 skill 的全部价值——排版只是载体，**译得地道、准确、像中文母语学者写的论文**才是目标。

## 工作流总览

```
源 PDF ──①提取──▶ 工作目录(tmp)  ──②翻译──▶ ZN.tex ──③编译──▶ ZN.pdf
         text + figures           学术化中文           XeLaTeX
```

逐段翻译再编译，不要想着一步到位。先把素材抽出来看清楚原文结构，再动笔。

> **跨工具说明**：本 skill 适用于任何支持 Skill 规范的 CLI / 智能体工具（Claude Code、Codex、
> Copilot CLI、Gemini CLI 等）。下文命令里写的 `~/.claude/skills/paper-translate-zh/` 是
> Claude Code 的默认安装路径；在其他工具下，请把它替换为本 skill 的**实际安装目录**
> （即包含本 `SKILL.md` 的目录）。

## ① 提取：文字 + 图片到工作目录

> **依赖 `pdf` skill**：本步骤的 PDF 处理建立在官方 `pdf` skill 之上。下面的
> `extract_pdf.py` 是与 `pdf` skill 同一套工具链（pdfplumber / pypdf / poppler）的便捷封装，
> 专为"翻译"场景一次性产出文字+整页渲染+裁图。遇到它处理不了的情况——**扫描件/图片型 PDF
> 需要 OCR、加密 PDF、表单、需要更精细的表格抽取**——先用 `pdf` skill 完成相应处理（如 OCR
> 成可搜索 PDF），再回到这里继续翻译。

为本次翻译建一个工作目录（默认放在源 PDF 同级的 `tmp/` 下，或用户指定处），跑提取脚本：

```bash
python3 ~/.claude/skills/paper-translate-zh/scripts/extract_pdf.py "<源.pdf>" "<workdir>"
```

产物：
- `full_text.txt` —— 全文文字，带 `==== PAGE n ====` 分页标记。**翻译的主要文本来源。**
- `pages/page_NN.png` —— 每页整页渲染图。**务必用 Read 工具看这些图**：纯文字抽取会丢两栏顺序、公式、上下标、图表位置——看页面图才能还原原文真实结构、准确转写公式、定位图注。
- `figures/p{n}_fig{k}.png` —— 自动裁出的图片区域，用于嵌入 `ZN.tex`。
- `manifest.json` —— 页数与图片清单（页码、bbox、像素尺寸）。

抽取不是万能的：矢量图、被切成多块的图、或自动裁剪没框准的图，从对应的 `pages/page_NN.png`
里按需重新裁剪即可（看图判断区域）。**判断哪些图是正文该保留的真图**（架构图、结果图、示意图），
丢弃页眉 logo、公式截块、装饰线。

## ② 翻译：写 ZN.tex

以 `assets/ZN_template.tex` 为骨架（含 ctex 中文环境、单栏版式、中文图表标题）。复制到工作目录改写：

```bash
cp ~/.claude/skills/paper-translate-zh/assets/ZN_template.tex "<workdir>/ZN.tex"
```

### 学术化中文 —— 核心要求

不是逐字直译，而是**用中文学术语体重写**。判断标准：一位该领域的中文学者读起来，
觉得这就是中文写就的论文，而非"翻译腔"。

- **意译优先于字面**。先读懂整句的论证，再用通顺的中文表达。英文长句拆成符合中文节奏的短句；
  被动语态多改主动（"It is observed that…" → "我们观察到……"或"实验表明……"）。
- **术语：中文为主，首次出现括注英文全称与缩写**，如"卷积神经网络（Convolutional Neural
  Network, CNN）"；此后用中文或公认缩写。译名取学界通用译法，拿不准时保留英文原词而非生造。
  GPU、BERT、Transformer 等无统一中文译名或约定俗成的，直接用原词。
- **学术语体**：用"本文""该方法""如式(3)所示""综上所述""值得注意的是"等学术连接词；
  避免口语（"我们发现一个很厉害的方法"）和机翻僵硬句式（"基于这个，我们做了那个"）。
- **数字与单位**：阿拉伯数字保留；单位规范（如 ms、GFLOPs）；百分数、区间照原文。
- **忠实**：不增删原意，不漏译句子，不臆造数据。看不懂的句子对照 `pages/` 页面图再译，
  绝不跳过或编造。
- **专有名词**：人名、机构名、数据集名（ImageNet、COCO）、方法缩写一般保留原文。

### 公式

数学公式用 **LaTeX 重排**（不是截图）：行内 `$...$`，独立公式用 `equation` 环境。
从 `pages/` 页面图准确转写每一个符号（上下标、希腊字母、求和/积分上下限最易错，逐一核对）。
公式里的变量含义在正文译文中说明。

### 图片与表格

- **图**：用 `\includegraphics` 嵌入 `figures/` 里的原图（或你从页面图裁出的图）。
  **图注译为中文**；图内坐标轴、图例等文字标签保留原文（无法编辑）。用 `[H]` 就近放在
  正文对应位置，顺序与原文一致。
- **表**：**重排为 LaTeX 中文三线表**（`booktabs`），表头与表注译成中文，数据照搬。
  小而规整的表都应重排；极复杂的表格无法重排时，才退而嵌入该表的页面裁图并译表注。

### 参考文献与引用超链接

**文献条目保留原文，不翻译**（作者、标题、出处、年份）。但要做成**可点击的超链接**：
用 `thebibliography` + `\bibitem{refN}` 录入文献，正文处用 `\cite{refN}` 引用——
hyperref 会自动把正文 `[n]` 变成可点击、跳转到对应文献条目的蓝色链接。`\bibitem` 标签
与正文 `\cite` 一一对应，按原文文献顺序逐条录入。

同理，图/表/公式/章节的交叉引用用 `\cref{label}`（如 `\cref{fig:overview}` → "图 1"），
也会生成可点击链接。模板已配好 `colorlinks` 与中文图表名，套用即可。

### 结构

按原文章节顺序组织：标题、作者、摘要、关键词、各章节、参考文献。
标题与各级小标题译为中文（大标题可括注原英文）。脚注、致谢按需翻译。

## ③ 编译：ZN.pdf

```bash
bash ~/.claude/skills/paper-translate-zh/scripts/compile_zh.sh "<workdir>/ZN.tex"
```

脚本用 `latexmk -xelatex`（中文必须 XeLaTeX）。失败时它打印精简错误摘要（file:line、
未定义引用、缺图、缺字体）。常见问题：

- **缺图**：`\includegraphics` 路径要相对 `ZN.tex`（模板已设 `\graphicspath{{figures/}}`，直接写 `p03_fig1.png`）。
- **特殊字符**：正文里的 `% & _ # $ ^ ~ \` 需转义或放进数学环境。
- **图太大溢出**：`\includegraphics[width=0.8\linewidth]{...}` 限宽。
- **编译卡死/字体错**：确认用的是 xelatex（脚本已指定），ctex 会自动回退到系统中文字体。

修好 `ZN.tex` 后重新编译，直到 `OK -> .../ZN.pdf`。

## 交付

报告 `ZN.pdf` 路径与页数。简述完成度（全文翻译 / 含 N 张图 / M 个表），并诚实说明任何
未能完美处理的地方（如某矢量图以页面裁图代替、某复杂表保留为图）。不要谎报已完成。

## 长论文提示

文章很长时，分章节翻译写入 `ZN.tex`，每完成几节可先试编译一次尽早暴露 LaTeX 错误，
而不是写完整篇才第一次编译。
