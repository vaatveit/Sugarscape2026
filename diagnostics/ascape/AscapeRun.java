import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

import org.ascape.model.HostCell;
import org.ascape.model.Scape;
import org.ascape.model.event.ScapeEvent;
import org.ascape.model.space.Array2DBase;
import org.ascape.model.space.Coordinate1DDiscrete;
import org.ascape.model.space.Coordinate2DDiscrete;
import org.ascape.runtime.NonGraphicRunner;
import org.ascape.runtime.Runner;
import org.ascape.view.nonvis.NonGraphicView;

import edu.brook.sugarscape.GAS_SexBase;
import edu.brook.sugarscape.SexualAgent;
import edu.brook.sugarscape.SugarAgent;
import edu.brook.sugarscape.SugarCell;

/**
 * Headless, seeded run of Ascape 5.6.1's Sugarscape sex model (edu.brook.sugarscape.GAS_SexBase: rules M, harvest,
 * metabolism, PromiscuousReprod, death): AscapeRun <fig 1|3|4|5> <seed> <steps> <map: ascape|book> [map file].
 * Ascape's own rules and agent code run unchanged; only stated parameters are set: the figure's endowment range
 * (p.57: 50-100; p.65: 10-40) and, for Figs III-3 and III-5, fertility ending 10 years earlier (p.64). "book" replaces
 * Ascape's generated two-Gaussian landscape with the book's map (sugarscape/maps/sugar-map.txt) and starts 400
 * founders as our runs do; "ascape" keeps Ascape's landscape and its 300 founders. The book states neither count.
 * Prints rows "RS,t,count,count,mean vision,mean metabolism" (the MASON harness's format; Ascape has no off-grid
 * agents), row 0 being the initial state.
 */
public class AscapeRun extends GAS_SexBase {
    static int[][] map;

    /** A SugarCell whose capacity comes from the book's map instead of Ascape's Gaussian mounds. */
    public static class BookCell extends SugarCell {
        public void initialize() {
            super.initialize();
            Coordinate2DDiscrete here = (Coordinate2DDiscrete) getCoordinate();
            sugar.setCapacity(map[here.getYValue()][here.getXValue()]);
            sugar.setQuantity(sugar.getCapacity());
        }
    }

    public void createScape() {
        super.createScape();
        if (map != null) {
            sugarscape.setPrototypeAgent(new BookCell());
            agents.setExtent(new Coordinate1DDiscrete(400));  // our founders' count (Ascape's sex model starts 300)
        }
    }

    public void createViews() {  // no Swing views; one listener printing our rows
        addView(new NonGraphicView("rows") {
            int t = 0;

            void row() {
                List<?> all = new ArrayList<Object>(agents);
                double vision = 0, metabolism = 0;
                for (Object o : all) {
                    vision += ((SugarAgent) o).getVision();
                    metabolism += ((SugarAgent) o).getSugarMetabolism();
                }
                int n = all.size();
                System.out.println("RS," + t++ + "," + n + "," + n + "," + (n == 0 ? "nan" : String.valueOf(vision / n))
                        + "," + (n == 0 ? "nan" : String.valueOf(metabolism / n)));
            }

            public void scapeStarted(ScapeEvent e) {
                Array2DBase space = (Array2DBase) sugarscape.getSpace();
                HostCell centre = (HostCell) space.get(new Coordinate2DDiscrete(25, 25));
                System.out.println("# periodic=" + space.getGeometry().isPeriodic() + " cells within vision 3="
                        + sugarscape.findWithin(centre.getCoordinate(), null, false, 3.0).size());
                row();
            }

            public void scapeIterated(ScapeEvent e) {
                row();
            }

            public void scapeStopped(ScapeEvent e) {
                System.out.flush();
                System.exit(0);
            }
        });
    }

    static void setStatic(String name, int value) throws Exception {
        Field f = SexualAgent.class.getDeclaredField(name);
        f.setAccessible(true);
        f.setInt(null, value);
    }

    public static void main(String[] args) throws Exception {
        int fig = Integer.parseInt(args[0]);
        String seed = args[1], steps = args[2];
        if (args[3].equals("book")) {
            map = new int[50][];
            try (BufferedReader in = new BufferedReader(new FileReader(args[4]))) {
                for (int r = 0; r < 50; r++) {
                    String[] cells = in.readLine().trim().split("\\s+");
                    map[r] = new int[50];
                    for (int c = 0; c < 50; c++) map[r][c] = Integer.parseInt(cells[c]);
                }
            }
        }
        if (fig == 3 || fig == 5) {  // p.64: fertility ends 10 years earlier
            setStatic("minFemaleReproductionEndsAge", 30);
            setStatic("maxFemaleReproductionEndsAge", 40);
            setStatic("minMaleReproductionEndsAge", 40);
            setStatic("maxMaleReproductionEndsAge", 50);
        }
        AscapeRun model = new AscapeRun();
        boolean low = fig == 4 || fig == 5;  // p.65: endowments 10-40
        model.setMinInitialSugar(low ? 10 : 50);
        model.setMaxInitialSugar(low ? 40 : 100);
        Runner runner = new NonGraphicRunner();
        runner.setRootScape(model);
        runner.open(new String[] {"RandomSeed=" + seed, "StopPeriod=" + steps}, true);
    }
}
