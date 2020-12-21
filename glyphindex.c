#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include "stb_truetype.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define UNICODE_MAX_CODEPOINT 0xFFFF

static int fail(lua_State* L, const char* err) {
    lua_pushnil(L);
    lua_pushstring(L, err);
    return 2;
}

static int f_get_missing_glyph(lua_State* L) {
    const char *filename = luaL_checkstring(L, 1);

    // load font file
    FILE *fp = NULL;
    stbtt_fontinfo info = { 0 };

    fp = fopen(filename, "rb");
    if (!fp) { return fail(L, strerror(errno)); }

    // get file size
    fseek(fp, 0, SEEK_END); int buf_size = ftell(fp); fseek(fp, 0, SEEK_SET);

    // read file
    unsigned char* data = malloc(buf_size);
    if (!data) { return fail(L, "Failed to allocate memory"); }
    int _ = fread(data, 1, buf_size, fp); (void) _;
    fclose(fp);
    fp = NULL;

    // load font
    int ok = stbtt_InitFont(&info, data, 0);
    if (!ok) { return fail(L, "Failed to load font"); }

    lua_newtable(L);
    for(int i = 0; i < UNICODE_MAX_CODEPOINT; i++) {
        lua_pushnumber(L, i);
        lua_pushboolean(L, stbtt_FindGlyphIndex(&info, i));
        lua_settable(L, -3);
    }

    return 1;
}

static const luaL_Reg modfuncs[] = {
    { "get_missing_glyphs", f_get_missing_glyph },
    { NULL, NULL }
};

int luaopen_glyphindex(lua_State *L) {
    luaL_newlib(L, modfuncs);
    return 1;
}