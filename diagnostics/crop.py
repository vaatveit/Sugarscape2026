"""Crop one PDF page to a PNG. Usage: crop.py <pdf> <page> <scale> <out.png> <x0,y0,x1,y1 as fractions>. Needs pypdfium2."""
import sys, pypdfium2 as pdfium
pdf, page, scale, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
box = [float(v) for v in sys.argv[5].split(",")]  # fractions x0,y0,x1,y1
img = pdfium.PdfDocument(pdf)[page - 1].render(scale=scale, grayscale=True).to_pil()
w, h = img.size
img.crop((int(box[0]*w), int(box[1]*h), int(box[2]*w), int(box[3]*h))).save(out)
