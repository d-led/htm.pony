// Pony's Pointer type offers no public way to read a byte, so the pixels stb
// allocates are copied into Pony's array here. Freeing is the caller's job on
// both sides: Pony owns the destination, stb owns the source.
#include <stddef.h>

void htm_copy_bytes(unsigned char *destination, const unsigned char *source, size_t length) {
  size_t index;
  for (index = 0; index < length; index++) {
    destination[index] = source[index];
  }
}
