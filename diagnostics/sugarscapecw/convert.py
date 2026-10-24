"""Convert SugarscapeCW 1.2.0 (NetLogo 5.3.1) to NetLogo 6 syntax, for running headless in NetLogo 6.4.

NetLogo 6's headless opener refuses 5.x models (only the desktop app auto-translates them), so this rewrites a copy:
each task placeholder (?, ?1, ?2) becomes a named argument of an anonymous procedure, and the version line is set to
6.4.0. Every replacement must match exactly the number of times given, and no placeholder may remain outside comments,
so a different source file fails loudly instead of converting half-way. The model's logic is unchanged.

With --nostack it also applies the NOSTACK ablation below (a departure from Watts' model, for diagnosis only).

Usage: convert.py <SugarscapeCW.nlogo> <output .nlogo> [--nostack]
"""
import re
import sys

# (old, new, expected count)
EDITS = [
    ("  foreach sugar-scape [\n    set cur-x 0\n    repeat length ? [",
     "  foreach sugar-scape [ row ->\n    set cur-x 0\n    repeat length row [", 1),
    ("  foreach spice-scape [\n    set cur-x 0\n    repeat length ? [",
     "  foreach spice-scape [ row ->\n    set cur-x 0\n    repeat length row [", 1),
    ("(read-from-string item cur-x ?))", "(read-from-string item cur-x row))", 2),
    ("n-values number-of-tags [ifelse-value", "n-values number-of-tags [ i -> ifelse-value", 1),
    ("[[array:item tags ?] of mum] [[array:item tags ?] of dad]",
     "[[array:item tags i] of mum] [[array:item tags i] of dad]", 1),
    ("n-values immune-system-length [ifelse-value", "n-values immune-system-length [ i -> ifelse-value", 1),
    ("[[array:item genetic-immune-system ?] of mum] [[array:item genetic-immune-system ?] of dad]",
     "[[array:item genetic-immune-system i] of mum] [[array:item genetic-immune-system i] of dad]", 1),
    ("(n-values vision [list 0 (? + 1)])", "(n-values vision [ i -> list 0 (i + 1)])", 1),
    ("(n-values vision [list 0 (-1 - ?)])", "(n-values vision [ i -> list 0 (-1 - i)])", 1),
    ("(n-values vision [list (? + 1) 0])", "(n-values vision [ i -> list (i + 1) 0])", 1),
    ("(n-values vision [list (-1 - ?) 0])", "(n-values vision [ i -> list (-1 - i) 0])", 1),
    ("(map [ifelse-value (? = 0) [1] [0]] (array:to-list tags))",
     "(map [ x -> ifelse-value (x = 0) [1] [0]] (array:to-list tags))", 1),
    ("filter [is-agent? ?] children", "filter [ c -> is-agent? c ] children", 1),
    ("      foreach surviving-children [\n        ask ? [", "      foreach surviving-children [ c ->\n        ask c [", 1),
    ("(map [ifelse-value (?1 = ?2) [0] [1]]", "(map [ [a b] -> ifelse-value (a = b) [0] [1]]", 1),
    ("  foreach trading-partners [\n;    set trade-prices []\n    trade-with-partner ?",
     "  foreach trading-partners [ p ->\n;    set trade-prices []\n    trade-with-partner p", 1),
    ("(map [log ? 10] given-list)", "(map [ x -> log x 10 ] given-list)", 1),
    ("      foreach code [\n        set num-matches num-matches + ifelse-value (? = ",
     "      foreach code [ b ->\n        set num-matches num-matches + ifelse-value (b = ", 1),
    ("  foreach code [\n    if ? != ", "  foreach code [ b ->\n    if b != ", 1),
    ("(map [?1 + ?2] tag-freqs", "(map [ [a b] -> a + b ] tag-freqs", 1),
    ("  foreach array:to-list disease-freq [\n    plotxy cur-disease-id ?",
     "  foreach array:to-list disease-freq [ f ->\n    plotxy cur-disease-id f", 1),
    ("  foreach sort-on [sugar-stock] people [", "  foreach sort-on [sugar-stock] people [ p ->", 1),
    ("[sugar-stock] of ?", "[sugar-stock] of p", 2),
    ("\nNetLogo 5.3.1\n", "\nNetLogo 6.4.0\n", 1),
]
# Optional ablation (not a conversion): the one-commodity rule M considers only unoccupied sites and the agent's own,
# as p.25 says, instead of every visible site (where agents can stack).
NOSTACK = [
    ("to move-to-nearest-best-patch\n  set potential-moves (patches at-points visible-points)\n",
     "to move-to-nearest-best-patch\n  set potential-moves (patches at-points visible-points) with [not any? people-here"
     " or self = [patch-here] of myself]\n", 1),
]
PLACEHOLDER = re.compile(r"(^|[\[\] (])\?[0-9]?($|[\[\] )])")


def convert(text: str, nostack: bool = False) -> str:
    for old, new, count in EDITS + (NOSTACK if nostack else []):
        found = text.count(old)
        if found != count:
            raise SystemExit(f"expected {count} of {old!r}, found {found}")
        text = text.replace(old, new)
    code = text.split("@#$#@#$#@")[0]
    left = [line for line in code.splitlines() if PLACEHOLDER.search(line.split(";")[0])]
    if left:
        raise SystemExit("placeholders left:\n" + "\n".join(left))
    return text


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8", newline="") as f:
        text = f.read()
    crlf = "\r\n" in text
    text = convert(text.replace("\r\n", "\n"), nostack="--nostack" in sys.argv[3:])
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write(text.replace("\n", "\r\n") if crlf else text)
    print(f"converted {src} -> {out}")
