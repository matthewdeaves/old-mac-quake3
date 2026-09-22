#!/usr/bin/env python3
"""Exercise actual rend2 uploads against a buffer-storage model and byte oracle."""
from pathlib import Path
import os
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'code/rend2/tr_vbo.c').read_text()
start = s.index('static byte rb_streamScratch[')
code = s[start:]
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef unsigned char byte;
#define SHADER_MAX_VERTEXES 8
#define SHADER_MAX_INDEXES 24
#define GL_ARRAY_BUFFER_ARB 0
#define GL_ELEMENT_ARRAY_BUFFER_ARB 1
#define GL_STREAM_DRAW_ARB 7
#define ATTR_POSITION 1
#define ATTR_NORMAL 2
#define ATTR_TEXCOORD 4
#define ATTR_LIGHTCOORD 8
#define ATTR_COLOR 16
#define ATTR_LIGHTDIRECTION 32
#define ATTR_TANGENT 64
#define ATTR_BITANGENT 128
#ifdef USE_VERT_TANGENT_SPACE
#define ATTR_BITS 255
#else
#define ATTR_BITS 63
#endif
typedef struct { int integer; } cvar_t;
static cvar_t mode;
static cvar_t *r_orphanBuffers = &mode;
typedef struct { int vertexesSize, ofs_xyz, ofs_normal, ofs_st, ofs_vertexcolor, ofs_lightdir, ofs_tangent, ofs_bitangent; } VBO_t;
typedef struct { int indexesSize; } IBO_t;
static VBO_t vbo;
static IBO_t ibo;
static struct {
 int numVertexes, numIndexes;
 float xyz[8][4], normal[8][4], texCoords[8][2][2], lightdir[8][4];
 float tangent[8][4], bitangent[8][4];
 byte vertexColors[8][4];
 unsigned indexes[24];
 VBO_t *vbo; IBO_t *ibo;
} tess;
static struct { struct { int c_dynamicVboDraws; } pc; } backEnd;
static byte gpu[2][2048];
static int sizes[2], dataCalls, subCalls;
#define Com_Memcpy memcpy
static void GLimp_LogComment(const char *s) { (void)s; }
static void R_BindVBO(VBO_t *v) { assert(v == &vbo); }
static void R_BindIBO(IBO_t *i) { assert(i == &ibo); }
static void qglBufferDataARB(int target, int size, const void *data, int usage) {
 assert(size > 0 && size <= 2048 && usage == GL_STREAM_DRAW_ARB);
 sizes[target] = size;
 memset(gpu[target], 0xA5, size);
 if (data) memcpy(gpu[target], data, size);
 dataCalls++;
}
static void qglBufferSubDataARB(int target, int offset, int size, const void *data) {
 assert(offset >= 0 && offset + size <= sizes[target]);
 memcpy(gpu[target] + offset, data, size);
 subCalls++;
}
'''
harness += code + r'''
#define RANGE(field, offset) do { \
 assert(!memcmp(gpu[0] + vbo.offset, tess.field, n * sizeof(tess.field[0]))); \
} while (0)
int main(void) {
 int offset = 0, m, n, bits, frame, i;
 vbo.ofs_xyz = offset; offset += sizeof(tess.xyz);
 vbo.ofs_normal = offset; offset += sizeof(tess.normal);
#ifdef USE_VERT_TANGENT_SPACE
 vbo.ofs_tangent = offset; offset += sizeof(tess.tangent);
 vbo.ofs_bitangent = offset; offset += sizeof(tess.bitangent);
#endif
 vbo.ofs_st = offset; offset += sizeof(tess.texCoords);
 vbo.ofs_vertexcolor = offset; offset += sizeof(tess.vertexColors);
 vbo.ofs_lightdir = offset; offset += sizeof(tess.lightdir);
 vbo.vertexesSize = offset;
 assert(offset == sizeof(rb_streamScratch));
 ibo.indexesSize = sizeof(tess.indexes);
 tess.vbo = &vbo; tess.ibo = &ibo;
 sizes[0] = vbo.vertexesSize; sizes[1] = ibo.indexesSize;
 for (frame = 0; frame < 3; frame++)
 for (m = 0; m < 3; m++)
 for (n = 0; n <= 8; n++)
 for (bits = 0; bits <= ATTR_BITS; bits++) {
  unsigned active = bits ? bits : ATTR_BITS;
  /* Byte patterns detect offset, extent and stale-data mistakes. */
  memset(tess.xyz, 11 + frame, sizeof(tess.xyz));
  memset(tess.normal, 22 + frame, sizeof(tess.normal));
  memset(tess.texCoords, 33 + frame, sizeof(tess.texCoords));
  memset(tess.vertexColors, 44 + frame, sizeof(tess.vertexColors));
  memset(tess.lightdir, 55 + frame, sizeof(tess.lightdir));
  memset(tess.tangent, 66 + frame, sizeof(tess.tangent));
  memset(tess.bitangent, 77 + frame, sizeof(tess.bitangent));
  for (i = 0; i < 24; i++) tess.indexes[i] = i % (n ? n : 1);
  tess.numVertexes = n; tess.numIndexes = n * 3;
  mode.integer = m; dataCalls = subCalls = 0;
  RB_UpdateVBOs(bits);
  if (active & ATTR_POSITION) RANGE(xyz, ofs_xyz);
  if (active & ATTR_NORMAL) RANGE(normal, ofs_normal);
  if (active & (ATTR_TEXCOORD | ATTR_LIGHTCOORD)) RANGE(texCoords, ofs_st);
  if (active & ATTR_COLOR) RANGE(vertexColors, ofs_vertexcolor);
  if (active & ATTR_LIGHTDIRECTION) RANGE(lightdir, ofs_lightdir);
#ifdef USE_VERT_TANGENT_SPACE
  if (active & ATTR_TANGENT) RANGE(tangent, ofs_tangent);
  if (active & ATTR_BITANGENT) RANGE(bitangent, ofs_bitangent);
#endif
  assert(!memcmp(gpu[1], tess.indexes, tess.numIndexes * sizeof(tess.indexes[0])));
  assert(dataCalls == ((m && n) ? 2 : 0));
  if (m == 2 || n == 0) assert(subCalls == 0);
 }
 puts("PASS: streaming uploads preserve all active vertex and index bytes");
 return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='q3-stream-test-') as tmp:
    src=Path(tmp)/'test.c'; src.write_text(harness)
    for tangent in (False, True):
        exe=Path(tmp)/('test-tangent' if tangent else 'test')
        subprocess.run([os.environ.get('CC','cc'), '-std=c99', '-Wall','-Wextra','-Werror',
                        '-fsanitize=address,undefined', *(['-DUSE_VERT_TANGENT_SPACE'] if tangent else []),
                        str(src),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
