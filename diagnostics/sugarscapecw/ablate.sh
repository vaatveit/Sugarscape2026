#!/bin/sh
# Ablations of SugarscapeCW's two departures from the text, on Figs III-1 and III-4 (founders at age 0, its presets):
# "nostack" restricts the one-commodity rule M to unoccupied sites and the agent's own (convert.py --nostack), and
# "wrap" makes the world a torus. Run build_and_run.sh first (it compiles CWRun into the same work folder).
# Usage: ablate.sh <SugarscapeCW.nlogo> <work folder> [seeds] [jobs]
set -e
SRC="$1"; WORK="$2"; SEEDS="${3:-10}"; JOBS="${4:-8}"
NETLOGO="${NETLOGO:-C:/Program Files/NetLogo 6.4.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK/ablate"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";"; W="$(cygpath -m "$WORK")"; H="$(cygpath -w "$HERE")";; *) SEP=":"; W="$WORK"; H="$HERE";; esac
python "$H/convert.py" "$SRC" "$W/SugarscapeCW6_nostack.nlogo" --nostack
cd "$WORK"
export CP="classes$SEP$NETLOGO/app/*" EXT="$NETLOGO/extensions" W
for v in base nostack wrap nostack+wrap; do
    for c in 1 4; do
        s=1; while [ "$s" -le "$SEEDS" ]; do echo "$c $s $v"; s=$((s + 1)); done
    done
done | xargs -P "$JOBS" -n 3 sh -c '
    model="$W/SugarscapeCW6.nlogo"; case "$2" in nostack*) model="$W/SugarscapeCW6_nostack.nlogo";; esac
    wrap=""; case "$2" in *wrap) wrap=wrap;; esac
    java -Xmx1g -Djava.awt.headless=true -Dfile.encoding=UTF-8 -Dnetlogo.extensions.dir="$EXT" --add-exports=java.base/java.lang=ALL-UNNAMED -cp "$CP" CWRun "$model" $0 $1 2500 zero $wrap > ablate/fig3-$0_$2_seed$1.csv 2>> ablate/errors.log'
[ -s ablate/errors.log ] && { echo "errors in $WORK/ablate/errors.log"; exit 1; }
echo "runs written to $WORK/ablate"
