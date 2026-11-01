/* The implementation of stb_image, in its own translation unit.
 *
 * The header is a library only when one file defines STB_IMAGE_IMPLEMENTATION.
 * Keeping that here means the Pony side never sees the header and the library is
 * compiled once.
 *
 * Only the formats a picture encoder actually meets are compiled in, and stdio
 * is left out: decoding goes through stbi_load_from_memory, so no file paths
 * cross the boundary and no C code opens anything.
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF

#include "stb_image.h"
