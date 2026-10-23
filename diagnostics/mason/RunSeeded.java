import ec.util.ParameterDatabase;
import java.io.InputStream;
import sim.app.sugarscape.Agent;
import sim.app.sugarscape.Sugarscape;

/**
 * Headless, seeded run of MASON's Sugarscape: RunSeeded <conf resource> <seed> <steps>.
 * Prints our own per-period rows, prefixed "RS,": t, MASON's population count, agents on the grid, and the on-grid
 * mean vision and sugar metabolism. (MASON's own statistics average over founders only: children are counted but
 * never added to active_agents.)
 */
public class RunSeeded {
    public static void main(String[] args) throws Exception {
        InputStream is = Sugarscape.class.getClassLoader().getResourceAsStream(args[0]);
        ParameterDatabase params = new ParameterDatabase(is);
        Sugarscape sugar = new Sugarscape(params, Long.parseLong(args[1]), 1);
        sugar.start();
        int steps = Integer.parseInt(args[2]);
        StringBuilder out = new StringBuilder();
        for (int t = 0; t < steps && sugar.schedule.time() < steps; t++) {
            int onGrid = 0;
            long vision = 0, metabolism = 0;
            Object[][] field = sugar.agents_grid.field;
            for (Object[] column : field)
                for (Object o : column)
                    if (o instanceof Agent a) { onGrid++; vision += a.vision; metabolism += a.metabolic_rate_sugar; }
            out.append("RS,").append(t).append(',').append(sugar.active_agents_count).append(',').append(onGrid)
               .append(',').append(onGrid == 0 ? "nan" : String.valueOf((double) vision / onGrid))
               .append(',').append(onGrid == 0 ? "nan" : String.valueOf((double) metabolism / onGrid)).append('\n');
            if (!sugar.schedule.step(sugar)) break;
        }
        sugar.finish();
        System.err.print(out);
        System.exit(0);
    }
}
