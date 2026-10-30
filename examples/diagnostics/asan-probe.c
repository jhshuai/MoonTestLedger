/* Project-authored Apache-2.0 detector fixture. Never linked into the product.
 * Deliberate invalid access in a separate process proves ASan is active. */
#include <stdlib.h>

int main(void) {
  char *p = malloc(8);
  if (p == NULL) return 2;
  p[0] = 1;
  free(p);
  return p[0];
}
