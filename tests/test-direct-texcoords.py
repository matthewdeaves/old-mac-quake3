#!/usr/bin/env python3
"""Check renderer pointer selection, vertex stride, and shader fallbacks."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'code/renderer/tr_shade.c').read_text()
def function(signature):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

harness = r'''
#include <assert.h>
#include <stdio.h>
typedef struct { int integer; } cvar_t;
cvar_t direct, primitives;
cvar_t *r_directTexCoords = &direct, *r_primitives = &primitives;
enum { TCGEN_TEXTURE, TCGEN_LIGHTMAP, TCGEN_IDENTITY, TCGEN_ENVIRONMENT_MAPPED, GL_FLOAT };
typedef struct { int numTexMods, tcGen; } textureBundle_t;
typedef struct { textureBundle_t bundle[2]; } shaderStage_t;
struct { float texCoords[4][2][2]; struct { float texcoords[2][4][2]; } svars; } tess;
static const unsigned char *pointer;
static int stride;
static void qglTexCoordPointer(int n, int type, int step, const void *data) {
    assert(n == 2 && type == GL_FLOAT);
    stride = step ? step : 2 * sizeof(float);
    pointer = data;
}
'''
harness += function('static int RB_DirectTexCoordSource(') + '\n'
harness += function('static void RB_StageTexCoordPointer(') + '\n'
harness += r'''
int main(void) {
    shaderStage_t stage;
    int enabled, prim, mods, gen, bundle, v, axis;
    for (v = 0; v < 4; v++) for (bundle = 0; bundle < 2; bundle++)
        for (axis = 0; axis < 2; axis++) {
            tess.texCoords[v][bundle][axis] = v * 100 + bundle * 10 + axis;
            tess.svars.texcoords[bundle][v][axis] = -1 - v * 100 - bundle * 10 - axis;
        }
    for (enabled = 0; enabled <= 1; enabled++)
    for (prim = 0; prim <= 3; prim++)
    for (mods = 0; mods <= 1; mods++)
    for (gen = TCGEN_TEXTURE; gen <= TCGEN_ENVIRONMENT_MAPPED; gen++)
    for (bundle = 0; bundle < 2; bundle++) {
        int eligible = enabled && prim != 3 && !mods && gen <= TCGEN_LIGHTMAP;
        direct.integer = enabled; primitives.integer = prim;
        stage.bundle[bundle].tcGen = gen;
        stage.bundle[bundle].numTexMods = mods;
        assert(RB_DirectTexCoordSource(&stage.bundle[bundle]) == (eligible ? gen : -1));
        RB_StageTexCoordPointer(&stage, bundle);
        for (v = 0; v < 4; v++) for (axis = 0; axis < 2; axis++) {
            const float *actual = (const float *)(pointer + v * stride);
            float expected = eligible ? tess.texCoords[v][gen][axis] : tess.svars.texcoords[bundle][v][axis];
            assert(actual[axis] == expected);
        }
    }
    puts("PASS: direct coordinates, both texture units, stride and shader fallbacks");
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='q3-texcoords-test-') as tmp:
    src = Path(tmp) / 'test.c'
    exe = Path(tmp) / 'test'
    src.write_text(harness)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra',
                    '-Werror', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
