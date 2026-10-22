"""Render a Markdown doc with screenshots to a portrait A4 Word file (reuses the audit report's converter).

Usage: python docs/_tools/build_doc_word.py docs/manual/user-manual.md "Documentation/CardKeep User Manual Rev 1.0.docx"
Images must sit on their own line: ![caption](relative/path.png), relative to the Markdown file.
"""
import pathlib
import sys

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.shared import Cm, Pt

import types  # noqa: E402

# build_mobile_report.py calls main() at the bottom; load it without that call.
_src = (pathlib.Path(__file__).parent / "build_mobile_report.py").read_text(encoding="utf-8")
mr = types.ModuleType("build_mobile_report")
exec(compile(_src.rsplit("\nmain()", 1)[0], "build_mobile_report.py", "exec"), mr.__dict__)


def main(src: str, out: str) -> None:
    src_p = pathlib.Path(src).resolve()
    mr.BASE = src_p.parent
    doc = Document()
    for s in doc.sections:
        s.orientation = WD_ORIENT.PORTRAIT
        s.page_width, s.page_height = Cm(21), Cm(29.7)
        s.left_margin = s.right_margin = s.top_margin = s.bottom_margin = Cm(1.8)
    st = doc.styles["Normal"]
    st.font.name = "Calibri"
    st.font.size = Pt(10)
    mr.md_to_docx(doc, src_p.read_text(encoding="utf-8"))
    out_p = pathlib.Path(out).resolve()
    out_p.parent.mkdir(parents=True, exist_ok=True)
    doc.save(out_p)
    print(out_p)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
