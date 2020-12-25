#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#define UNICODE_MAX_CODEPOINT 0xFFFF

static void die(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");

    fprintf(
        stderr,
        "backupfont - Get a list of fonts that supports the codepoints.\n"
        "Usage:\n"
        "\n"
        "\tbackupfont outfile font1 font2 ... fontn\n"
        "\n"
        "Limitations:\n"
        "- You can only specify up to 255 fonts at 1 time.\n"
    );
    exit(EXIT_FAILURE);
}

// convert integer to little-endian if necessary
static uint32_t conv_uint(int n) {
    int x = 1;
    if ( *((char*) &x) == 1 ) {
        return n;
    } else {
         return ((n>>24)&0xff) |
                ((n<<8)&0xff0000) |
                ((n>>8)&0xff00) |
                ((n<<24)&0xff000000);
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) { die("Insufficient arguments."); }
    if (argc > 257) { die("Too much arguments."); }
    char codepoints[UNICODE_MAX_CODEPOINT];

    FILE *fp = NULL;
    stbtt_fontinfo info = { 0 };

    for (int i = 2; i < argc; i++) {
        // open font
        const char* filename = argv[i];
        fp = fopen(filename, "rb");
        if (!fp) { continue; }

        // get filesize
        fseek(fp, 0, SEEK_END); int buf_size = ftell(fp); fseek(fp, 0, SEEK_SET);

        // read file
        unsigned char* data = malloc(buf_size);
        if (!data) { die("Unable to allocate memory."); }
        int _ = fread(data, 1, buf_size, fp); (void) _;
        fclose(fp);
        fp = NULL;

        // open font
        int ok = stbtt_InitFont(&info, data, 0);
        if (!ok) { continue; }

        // get codepoint available
        for(uint32_t j = 0; j < UNICODE_MAX_CODEPOINT; j++) {
            if (stbtt_FindGlyphIndex(&info, j) != 0) {
                codepoints[j] = i - 1;
            }
        }
        
        free(data);
    }

    // write data to outfile
    const char* output = argv[1];
    fp = fopen(output, "wb");
    if (!fp) { die("Unable to open output file."); }

    // write number of fonts passed to us
    char fontlen = (char) argc - 2;
    fwrite((void*) &fontlen, sizeof(char), 1, fp);

    // write fonts passed to us
    for (int i = 2; i < argc; i++) {
        uint32_t len = conv_uint(strlen(argv[i]));
        fwrite((void*) &len, sizeof(int), 1, fp);
        fwrite((void*) argv[i], sizeof(char), len, fp);
    }

    // write the codepoint data
    fwrite((void*) codepoints, sizeof(char), UNICODE_MAX_CODEPOINT, fp);
    fclose(fp);
    fp = NULL;

    return EXIT_SUCCESS;
}