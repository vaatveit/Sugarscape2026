#!/bin/sh
# Build MASON's Sugarscape (Bigbee, Cioffi-Revilla and Luke 2007) headless and run its Chapter III configs.
# Usage: build_and_run.sh <unzipped source-archive folder> <work folder> [seeds] [jobs]
# The archive's .svn pristine copies hold the project's own lib/ jars (mason.jar, JFreeChart 1.0.13, JCommon 1.0.16)
# and its util/ sources, which the checkout itself leaves empty. Needs a JDK (tested with 22) on the PATH.
set -e
SRC="$1/mason-sugarscape/trunk"; WORK="$2"; SEEDS="${3:-10}"; JOBS="${4:-8}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK/lib" "$WORK/src/sim/app/sugarscape/util" "$WORK/classes/conf" "$WORK/runs"
for j in mason.jar jfreechart-1.0.13.jar jcommon-1.0.16.jar; do cp "$SRC/lib/.svn/text-base/$j.svn-base" "$WORK/lib/$j"; done
cp "$SRC"/sim/app/sugarscape/*.java "$WORK/src/sim/app/sugarscape/"
for f in "$SRC"/sim/app/sugarscape/util/.svn/text-base/*.java.svn-base; do cp "$f" "$WORK/src/sim/app/sugarscape/util/$(basename "$f" .svn-base)"; done
cp "$SRC"/conf/* "$WORK/classes/conf/"
sed -i 's/^chart_display=true/chart_display=false/' "$WORK"/classes/conf/fig3-*.conf
SEP=":"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";";; esac
CP="classes${SEP}lib/mason.jar${SEP}lib/jfreechart-1.0.13.jar${SEP}lib/jcommon-1.0.16.jar"
cd "$WORK"
javac -nowarn -encoding ISO-8859-1 -d classes -cp "$CP" $(find src -name '*.java' ! -name 'SugarscapeWithUIHigh.java' \
    ! -name 'QuickSortTester.java' ! -name 'ResultsGrapher.java' ! -name 'ParamSweeper.java') "$HERE/RunSeeded.java"
for c in 1 3 4 5; do
    steps=2500; [ "$c" = 5 ] && steps=1500
    s=1; while [ "$s" -le "$SEEDS" ]; do echo "$c $s $steps"; s=$((s + 1)); done
done | xargs -P "$JOBS" -n 3 sh -c 'java -Djava.awt.headless=true -cp "'"$CP"'" RunSeeded conf/fig3-$0.conf $1 $2 2> runs/fig3-$0_seed$1.csv > /dev/null'
echo "runs written to $WORK/runs; score them with: python diagnostics/mason_compare.py $WORK/runs"
