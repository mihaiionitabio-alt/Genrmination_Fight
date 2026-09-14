"""Flatten the LaTeX book into plain text and emit it as server-only Lua comments.

The audience is another model reading the place, so the whole reference goes in
rather than a summary: chapters in book order, Revision 5 first because it
supersedes everything before it. Two paragraphs that Revision 5 proved wrong are
annotated where they stand, so a reader who lands on C01 sees the correction
there instead of having to reach chapter 1 to learn it is false.
"""
from pathlib import Path
import re, json

BOOK = Path('/root/book') if False else Path.home() / 'mnt/game/documentation/Genrmination_Fight'
OUT = Path.home() / 'mnt/game/revision5/docgen'
MASTER = BOOK / 'Genrmination_Fight.tex'
LIMIT = 170000          # well under Studio's 200,000-char Script.Source cap

# ---- chapter order, taken from the master file so the two cannot drift -----
order = re.findall(r'\\input\{chapters/([^}]+)\}', MASTER.read_text(encoding='utf-8'))

# ---- corrections applied in place -----------------------------------------
CORRECTIONS = [
 ("The building itself was not moved back.",
  "The building itself was not moved back. "
  "*** CORRECTED BY REVISION 5: this conclusion is wrong. The laboratory itself "
  "was the displaced object, and it WAS moved back, by (+25.142857, +23.25, "
  "-91.285714). The lounge, hatch rim, ground plane and all three spawns were "
  "already correct and should never have been touched. Verified against the "
  "authored node translations in D:\\game\\4\\Export.gltf. See chapter 'Revision 5'. ***"),
 ("Do not move the lounge twice; LabFrameAligned records the one-time migration.",
  "Do not move the lounge twice; LabFrameAligned records the one-time migration. "
  "*** CORRECTED BY REVISION 5: do not follow this. The lounge migration was "
  "itself the error and has been reversed; the LabFrameAligned marker is cleared. "
  "Do not compose a global frame from Roof_1 or any other landmark part. "
  "LabSpatial is retired to ServerStorage.LabSpatial_RETIRED_revision4 and its "
  "frame evaluates to identity against the restored datum. ***"),
]

# ---- LaTeX -> readable text -------------------------------------------------
def detex(s: str) -> str:
    s = re.sub(r'(?m)^\s*%.*$', '', s)
    s = s.replace('\\allowbreak{}', '')
    # structure becomes headings a reader can scan
    s = re.sub(r'\\chapter\*?\{(.+?)\}', lambda m: '\n\n' + '=' * 78 + '\nCHAPTER: ' + m.group(1) + '\n' + '=' * 78 + '\n', s)
    s = re.sub(r'\\section\*?\{(.+?)\}',    lambda m: '\n\n## ' + m.group(1) + '\n', s)
    s = re.sub(r'\\subsection\*?\{(.+?)\}', lambda m: '\n\n### ' + m.group(1) + '\n', s)
    s = re.sub(r'\\subsubsection\*?\{(.+?)\}', lambda m: '\n\n#### ' + m.group(1) + '\n', s)
    # environments we only need the contents of
    for env in ('center','itemize','enumerate','description','tabular','longtable',
                'quote','flushleft','tikzpicture','figure','table','Verbatim','verbatim'):
        s = re.sub(r'\\begin\{' + env + r'\}(\[[^\]]*\])?(\{[^}]*\})?', '', s)
        s = re.sub(r'\\end\{' + env + r'\}', '', s)
    s = re.sub(r'\\(item)\s*', '\n  - ', s)
    s = re.sub(r'\\(toprule|midrule|bottomrule|hline|centering|par|noindent|small|scriptsize|footnotesize|raggedright|bfseries|sffamily|ttfamily)\b', '', s)
    # inline markup keeps only its argument
    for cmd in ('texttt','textbf','textit','emph','textsf','text','mbox','url','href','label','ref','autoref'):
        s = re.sub(r'\\' + cmd + r'\*?\{([^{}]*)\}', r'\1', s)
        s = re.sub(r'\\' + cmd + r'\*?\{([^{}]*)\}', r'\1', s)
    s = re.sub(r'\\multicolumn\{\d+\}\{[^}]*\}\{([^{}]*)\}', r'\1', s)
    s = s.replace('\\\\', '\n')
    s = s.replace('&', '  |  ')
    s = re.sub(r'\$([^$]*)\$', r'\1', s)
    s = s.replace('\\times', 'x').replace('\\rightarrow', '->').replace('\\pm', '+/-')
    s = s.replace('\\textbackslash ', '\\').replace('\\textbackslash', '\\')
    s = re.sub(r'\\[a-zA-Z@]+\*?(\[[^\]]*\])?', '', s)   # any command left over
    s = s.replace('``', '"').replace("''", '"')
    for a, b in (('\\_','_'), ('\\&','&'), ('\\%','%'), ('\\#','#'), ('\\$','$'), ('~',' ')):
        s = s.replace(a, b)
    s = s.replace('{', '').replace('}', '')
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r'\n{3,}', '\n\n', s)
    return s.strip()

parts = []
for name in order:
    raw = (BOOK / 'chapters' / name).read_text(encoding='utf-8')
    for old, new in CORRECTIONS:
        if old in raw or old.replace('_', '\\_\\allowbreak{}') in raw:
            pass
    parts.append((name, detex(raw)))

body = []
for name, text in parts:
    body.append(f'\n\n<<< source chapter: chapters/{name} >>>\n{text}')
doc = '\n'.join(body)

# corrections are applied after flattening, so the marker text is matched
# against the same plain form a reader will see
applied = 0
for old, new in CORRECTIONS:
    if old in doc:
        doc = doc.replace(old, new); applied += 1
print('corrections applied:', applied, 'of', len(CORRECTIONS))

HEADER = (
 "GENRMINATION_FIGHT  --  COMPLETE WRITTEN REFERENCE\n"
 "Revision 5, 14 September 2026.  Place 137098589879404.\n"
 "\n"
 "This is the full engineering record, embedded verbatim for AI models reading\n"
 "the place directly (Claude, ChatGPT, DeepSeek and others). It is a comment:\n"
 "Lua discards it at compile time, so it has no runtime cost, and it lives in\n"
 "ServerStorage, which never replicates to clients.\n"
 "\n"
 "AUTHORITY: the 'Revision 5' chapter supersedes every chapter after it wherever\n"
 "they disagree. Revision 4's C01/C02 conclusions are WRONG and are annotated in\n"
 "place with '*** CORRECTED BY REVISION 5 ***'.\n"
 "\n"
 "STANDING RULES FOR ANY MODEL MODIFYING THIS GAME:\n"
 "  1. Never compose a global coordinate frame from a landmark part.\n"
 "  2. Never store world coordinates in gameplay code. Resolve positions at\n"
 "     runtime from RoomIndex, CollectionService tags, or instance lookup.\n"
 "  3. Fixes belong in SeedLabGenerator.lua as well as the installed scripts;\n"
 "     the installed scripts are its output and a rebuild reverts them.\n"
 "  4. Declare locals above every function that names them. This project has\n"
 "     lost threads to the nil-global trap five separate times.\n"
 "  5. Verify with a numeric scene query, not a single play-through.\n"
 "  6. Do not transform live instances. If unavoidable, make it idempotent and\n"
 "     assert a known part lands where expected before touching the rest.\n"
)

# ---- split on paragraph boundaries, under the Script.Source cap ------------
chunks, cur = [], ''
for para in doc.split('\n\n'):
    piece = para + '\n\n'
    if len(cur) + len(piece) > LIMIT and cur:
        chunks.append(cur); cur = piece
    else:
        cur += piece
if cur.strip():
    chunks.append(cur)

names = ['GameDocumentation'] + [f'GameDocumentationAnnex{i}' for i in range(2, len(chunks) + 1)]
manifest = []
for i, (nm, chunk) in enumerate(zip(names, chunks), start=1):
    # pick a long-bracket level the content cannot terminate
    level = '='* 8
    while ']' + level + ']' in chunk:
        level += '='
    text = (f'--[{level}[\n{HEADER}\n'
            f'Reference part {i} of {len(chunks)}.\n'
            + '=' * 78 + '\n'
            + chunk.replace('\r', '') +
            f'\n]{level}]\n'
            f'return {{revision=5,part={i},parts={len(chunks)},'
            f'reference="Server-only written reference; never required by gameplay"}}\n')
    p = OUT / f'ServerStorage.{nm}.lua'
    p.write_text(text, encoding='utf-8')
    manifest.append({'path': f'ServerStorage.{nm}', 'cls': 'ModuleScript',
                     'file': p.name, 'bytes': len(text.encode('utf-8'))})
    print(f'{nm}: {len(text):,} chars')

(OUT / 'docs-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('total chars:', sum(len(c) for c in chunks), 'parts:', len(chunks))
