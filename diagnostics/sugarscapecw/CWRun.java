// Runs SugarscapeCW (Christopher Watts, NetLogo 5.3.1; CoMSES codebase 4688, release 1.2.0) headless in NetLogo 6.4 on
// the settings of Figs III-1, III-3, III-4 and III-5. It starts from the model's own Chapter III preset
// (setup-scenario-6: Fig III-5's settings, rule S as "Sexual") and sets only the figure's stated endowment and
// fertility ages, the founders' ages, the seed and the run length. Prints one row per period in the MASON harness's
// format: RS,t,population,population,mean vision,mean metabolism.
// Optional trailing words: "wrap" makes the world a torus (__change-topology), which Watts' world is not (an ablation
// for diagnosis); "probe" adds a row per period, P,t,births,fertile-age agents,those also holding their endowment,
// mean children of women past childbearing, mean endowment (each agent's fertility requirement).
// Usage: CWRun <SugarscapeCW.nlogo> <figure 1|3|4|5> <seed> <steps> <founders: zero|spread> [wrap] [probe]
import org.nlogo.headless.HeadlessWorkspace;

public class CWRun {
    public static void main(String[] args) throws Exception {
        String model = args[0];
        int fig = Integer.parseInt(args[1]), seed = Integer.parseInt(args[2]), steps = Integer.parseInt(args[3]);
        boolean zero = args[4].equals("zero");
        boolean low = fig == 4 || fig == 5;    // p.65: endowments 10-40
        boolean early = fig == 3 || fig == 5;  // p.64: fertility ends 10 years earlier
        HeadlessWorkspace ws = HeadlessWorkspace.newInstance();
        try {
            ws.open(model);
            ws.command("setup-scenario-6");
            ws.command("set min-endowment " + (low ? 10 : 50) + " set max-endowment " + (low ? 40 : 100));
            ws.command("set min-fertility-end-male " + (early ? 40 : 50) + " set max-fertility-end-male " + (early ? 50 : 60));
            ws.command("set min-fertility-end-female " + (early ? 30 : 40) + " set max-fertility-end-female " + (early ? 40 : 50));
            ws.command("set initial-age-0? " + zero + " set rng-seed " + seed + " set max-ticks " + (steps + 1));
            java.util.List<String> extra = java.util.Arrays.asList(args).subList(5, args.length);
            boolean probe = extra.contains("probe");
            if (extra.contains("wrap")) ws.command("__change-topology true true");
            ws.command("setup");
            System.out.println("# wrap " + ws.report("(list world-width world-height ([patch-at -1 0] of patch 0 0 != nobody)"
                + " ([patch-at 0 -1] of patch 0 0 != nobody))"));
            System.out.println("# " + ws.report("(list reproduction initial-population scape-type growback-method"
                + " sugar-growback-rate mean-vision mean-metabolic-rate min-endowment max-endowment min-death-age"
                + " max-death-age min-fertility-start max-fertility-start min-fertility-end-female"
                + " max-fertility-end-female min-fertility-end-male max-fertility-end-male initial-age-0?"
                + " inheritance? last-rng-seed)"));
            for (int t = 0; t <= steps; t++) {
                if (t > 0) ws.command("go");
                double n = ((Double) ws.report("count people")).doubleValue();
                String v = n == 0 ? "nan" : ws.report("mean [vision] of people").toString();
                String m = n == 0 ? "nan" : ws.report("mean [metabolic-rate] of people").toString();
                System.out.println("RS," + t + "," + (long) n + "," + (long) n + "," + v + "," + m);
                if (probe && n > 0) System.out.println("P," + t + "," + ws.report("(list num-babies"
                    + " count people with [fertile?] count people with [fertile? and sugar-stock >= endowment]"
                    + " ifelse-value any? people with [sex = 0 and age > fertility-end]"
                    + " [mean [length children] of people with [sex = 0 and age > fertility-end]] [0]"
                    + " mean [endowment] of people)")
                    .toString().replace("[", "").replace("]", "").replace(" ", ","));
                if (t % 500 == 0) System.out.println("# t=" + t + " sites holding 2+ agents, most on one site: "
                    + ws.report("(list count patches with [count people-here > 1] max [count people-here] of patches)"));
                if (n == 0) break;
            }
        } finally {
            ws.dispose();
        }
    }
}
