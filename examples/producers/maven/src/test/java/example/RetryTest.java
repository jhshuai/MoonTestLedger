// Project-authored producer input, Apache-2.0; deterministic fail-then-pass.
package example;

import org.junit.Test;
import static org.junit.Assert.assertTrue;

public class RetryTest {
    private static int attempts = 0;
    @Test public void recovers() { assertTrue("first attempt fails", ++attempts > 1); }
}
