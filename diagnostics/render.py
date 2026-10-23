"""Render every page of each chapter PDF in a folder to grayscale PNGs (pages/<tag>/pNNN.png), for digitizing figures.
Usage: render.py <pdf folder> <out folder> <scale>. Needs pypdfium2; the book PDFs are not in the repository."""
import sys, pathlib, pypdfium2 as pdfium
src = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2]); scale = float(sys.argv[3])
for pdf in sorted(src.glob("*.pdf")):
    tag = pdf.stem.split("_")[-1]
    d = out / tag; d.mkdir(parents=True, exist_ok=True)
    doc = pdfium.PdfDocument(str(pdf))
    for i in range(len(doc)):
        page = doc[i]
        if i == 0: print(tag, len(doc), page.get_size())
        img = page.render(scale=scale, grayscale=True).to_pil()
        img.save(d / f"p{i+1:03d}.png", optimize=True)
