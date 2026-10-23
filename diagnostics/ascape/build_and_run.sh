#!/bin/sh
# Run Ascape 5.6.1's Sugarscape sex model headless on Figs III-1, III-3, III-4 and III-5, on Ascape's own landscape
# and on the book's map. Usage: build_and_run.sh <Ascape_5.6.1.jar> <work folder> [seeds] [jobs]
# The jar is the release at sourceforge.net/projects/ascape/files/Ascape/5.6.1/release/ (6.0 MB); it carries the
# compiled framework and the edu.brook.sugarscape models. Needs a JDK (tested with 22) on the PATH.
set -e
JAR="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; WORK="$2"; SEEDS="${3:-10}"; JOBS="${4:-8}"
HERE="$(cd "$(dirname "$0")" && pwd)"; MAP="$HERE/../../sugarscape/maps/sugar-map.txt"
mkdir -p "$WORK/classes" "$WORK/runs"
SEP=":"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";"; JAR="$(cygpath -w "$JAR")"; MAP="$(cygpath -w "$MAP")";; esac
cd "$WORK"
javac -nowarn -d classes -cp "$JAR" "$HERE/AscapeRun.java"
for m in ascape book; do
    for c in 1 3 4 5; do
        steps=2500; [ "$c" = 5 ] && steps=1500
        s=1; while [ "$s" -le "$SEEDS" ]; do echo "$c $s $steps $m"; s=$((s + 1)); done
    done
done | xargs -P "$JOBS" -n 4 sh -c 'java -Djava.awt.headless=true -cp "classes'"$SEP$JAR"'" AscapeRun $0 $1 $2 $3 "'"$MAP"'" > runs/fig3-$0_$3_seed$1.csv 2>> runs/errors.log'
[ -s runs/errors.log ] && { echo "errors in $WORK/runs/errors.log"; exit 1; }
echo "runs written to $WORK/runs; score them with: python diagnostics/ascape_compare.py $WORK/runs"
