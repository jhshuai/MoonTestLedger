// Project-authored producer input, Apache-2.0.
package example;

import java.util.Arrays;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import static org.junit.Assert.assertTrue;

@RunWith(Parameterized.class)
public class ParameterizedTest {
    @Parameterized.Parameters(name = "amount={0}")
    public static Iterable<Object[]> data() { return Arrays.asList(new Object[][] { {0}, {100} }); }
    @Parameterized.Parameter public int amount;
    @Test public void acceptsAmount() { assertTrue(amount >= 0); }
}
