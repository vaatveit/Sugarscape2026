"""Paths for diagnostics: the repository root, and page images of the book (not in the repository).

Book pages are PNGs rendered from the chapter PDFs by render.py, one folder per chapter tag (e.g. pages/pc/p012.png
is Chapter III's twelfth page, p.65). Set BOOK_PAGES to the folder holding those chapter folders.
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def book_page(chapter: str, name: str) -> Path:
    pages = os.environ.get("BOOK_PAGES")
    if not pages:
        raise SystemExit("Set BOOK_PAGES to the folder of rendered book pages (see diagnostics/_paths.py).")
    return Path(pages) / chapter / name
