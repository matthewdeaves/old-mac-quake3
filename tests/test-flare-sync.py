#!/usr/bin/env python3
"""Exercise the real flare visibility functions with a recorded depth read."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'code/renderer/tr_flares.c').read_text()

def function(signature):
    start = source.index(signature)
    opening = source.index('{', start)
    level = 1
    end = opening + 1
    while level:
        level += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

harness = r'''
#include <assert.h>
#include <stdio.h>
typedef int qboolean;
enum { qfalse, qtrue, GL_DEPTH_COMPONENT, GL_FLOAT };
typedef struct { int integer; float value; } cvar_t;
cvar_t noFinish, finish, fade = {0, 7};
cvar_t *r_flareNoFinish = &noFinish, *r_finish = &finish, *r_flareFade = &fade;
typedef struct {
    int windowX, windowY, fadeTime;
    float eyeZ, drawIntensity;
    qboolean visible;
} flare_t;
struct { qboolean finishCalled; } glState;
struct {
    struct { int c_flareTests; } pc;
    struct { float projectionMatrix[16]; } viewParms;
    struct { int time; } refdef;
} backEnd;
static int reads;
static float testDepth;
static void qglReadPixels(int x, int y, int w, int h, int format, int type, float *depth) {
    assert(x == 12 && y == 34 && w == 1 && h == 1);
    assert(format == GL_DEPTH_COMPONENT && type == GL_FLOAT);
    *depth = testDepth;
    reads++;
}
'''
harness += function('static void RB_UpdateFlareFade( flare_t *f )')
harness += '\n' + function('void RB_TestFlare( flare_t *f )')
harness += r'''
int main(void) {
    int mode, enabled, initial, occluded;
    backEnd.refdef.time = 1000;
    backEnd.viewParms.projectionMatrix[14] = -100;
    backEnd.viewParms.projectionMatrix[11] = -1;
    backEnd.viewParms.projectionMatrix[10] = -2;
    for (mode = -1; mode <= 1; mode++)
    for (enabled = 0; enabled <= 1; enabled++)
    for (initial = 0; initial <= 1; initial++)
    for (occluded = 0; occluded <= 1; occluded++) {
        flare_t f = {12, 34, 0, -100, 0, qfalse};
        finish.integer = mode;
        noFinish.integer = enabled;
        glState.finishCalled = initial;
        testDepth = occluded ? 0 : 1;
        reads = 0;
        backEnd.pc.c_flareTests = 0;
        RB_TestFlare(&f);
        assert(reads == 1 && backEnd.pc.c_flareTests == 1);
        assert(glState.finishCalled == ((enabled && mode == 0) ? initial : 0));
        assert(f.visible == !occluded);
        assert(occluded ? f.drawIntensity == 0 : f.drawIntensity > 0);
    }
    puts("PASS: flare readback, visibility, fade and finish policy");
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='q3-flare-test-') as tmp:
    src = Path(tmp) / 'test.c'
    exe = Path(tmp) / 'test'
    src.write_text(harness)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra',
                    '-Werror', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
