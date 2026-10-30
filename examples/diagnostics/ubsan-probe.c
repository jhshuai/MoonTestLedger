/* Project-authored Apache-2.0 detector fixture. Never linked into the product.
 * Deliberate invalid shift in a separate process proves UBSan is active. */
int main(void) {
  volatile int shift = 32;
  return 1 << shift;
}
