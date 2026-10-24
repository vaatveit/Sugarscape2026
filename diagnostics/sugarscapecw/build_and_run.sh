#!/bin/sh
# Run SugarscapeCW 1.2.0 (Watts, NetLogo 5.3.1) headless in NetLogo 6.4 on Figs III-1, III-3, III-4 and III-5, with
# founders at age 0 (the model's presets) and at spread ages (its option, U[0, 80]).
# Usage: build_and_run.sh <SugarscapeCW.nlogo> <work folder> [seeds] [jobs]
# The model is the CoMSES release (codebase 4688, version 1.2.0, code/SugarscapeCW.nlogo). NetLogo 6.4.0 is the
# installer at downloads.netlogo.org/6.4.0/; set NETLOGO if it isn't in C:/Program Files/NetLogo 6.4.0. Needs a JDK
# (tested with 22) and Python on the PATH.
set -e
SRC="$1"; WORK="$2"; SEEDS="${3:-10}"; JOBS="${4:-8}"
NETLOGO="${NETLOGO:-C:/Program Files/NetLogo 6.4.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK/classes" "$WORK/runs"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";"; W="$(cygpath -w "$WORK")"; H="$(cygpath -w "$HERE")";; *) SEP=":"; W="$WORK"; H="$HERE";; esac
python "$H/convert.py" "$SRC" "$W/SugarscapeCW6.nlogo"
cd "$WORK"
javac -nowarn -d classes -cp "$NETLOGO/app/*" "$H/CWRun.java"
export CP="classes$SEP$NETLOGO/app/*" EXT="$NETLOGO/extensions" MODEL="$W/SugarscapeCW6.nlogo"
for f in zero spread; do
    for c in 1 3 4 5; do
        steps=2500; [ "$c" = 5 ] && steps=1500
        s=1; while [ "$s" -le "$SEEDS" ]; do echo "$c $s $steps $f"; s=$((s + 1)); done
    done
done | xargs -P "$JOBS" -n 4 sh -c 'java -Xmx1g -Djava.awt.headless=true -Dfile.encoding=UTF-8 -Dnetlogo.extensions.dir="$EXT" --add-exports=java.base/java.lang=ALL-UNNAMED -cp "$CP" CWRun "$MODEL" $0 $1 $2 $3 > runs/fig3-$0_$3_seed$1.csv 2>> runs/errors.log'
[ -s runs/errors.log ] && { echo "errors in $WORK/runs/errors.log"; exit 1; }
echo "runs written to $WORK/runs; score them with: python diagnostics/sugarscapecw_compare.py $WORK/runs"
