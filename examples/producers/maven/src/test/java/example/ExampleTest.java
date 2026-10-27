// Project-authored producer input, Apache-2.0; deliberately failing cases.
package example;

import org.junit.Ignore;
import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class ExampleTest {
    @Test public void passes() { System.out.println("captured payment output: 中文 <receipt>"); }
    @Test public void fails() { assertEquals("payment rejected <declined>", 1, 2); }
    @Test public void errors() { throw new IllegalStateException("service unavailable"); }
    @Ignore("requires external service") @Test public void offline() { }
}
