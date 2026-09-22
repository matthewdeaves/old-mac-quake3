#!/usr/bin/env python3
"""Compare the actual scalar mixer paths across samples and chunk boundaries."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'code/client/snd_mix.c').read_text()
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
#include <string.h>
#define SND_CHUNK_SIZE 1024
#define PAINTBUFFER_SIZE 8192
typedef struct { int left, right; } portable_samplepair_t;
typedef struct sndBuffer { short sndChunk[SND_CHUNK_SIZE]; struct sndBuffer *next; } sndBuffer;
typedef struct { sndBuffer *soundData; } sfx_t;
typedef struct { int leftvol, rightvol, doppler; float oldDopplerScale, dopplerScale; } channel_t;
typedef struct { int integer; } cvar_t;
static cvar_t toggle;
static cvar_t *s_mixScalarChunks = &toggle;
static portable_samplepair_t paintbuffer[PAINTBUFFER_SIZE];
static int snd_vol;
'''
harness += function('static void S_MixScalarChunks(') + '\n'
harness += function('static void S_PaintChannelFrom16_scalar(') + '\n'
harness += r'''
static unsigned state = 12345;
static unsigned randomValue(void) { state = state * 1664525u + 1013904223u; return state; }
int main(void) {
    sndBuffer chunks[8];
    sfx_t sound;
    channel_t channel;
    portable_samplepair_t expected[PAINTBUFFER_SIZE], initial[PAINTBUFFER_SIZE];
    int test, i, j;
    int offsets[] = {0, 1, 1023, 1024, 1025, 2047};
    int counts[] = {0, 1, 2, 7, 1023, 1024, 1025, 2049};
    for (i = 0; i < 8; i++) {
        chunks[i].next = &chunks[(i + 1) % 8];
        for (j = 0; j < SND_CHUNK_SIZE; j++) chunks[i].sndChunk[j] = (short)randomValue();
        chunks[i].sndChunk[0] = -32768;
        chunks[i].sndChunk[1] = 32767;
    }
    sound.soundData = chunks;
    for (test = 0; test < 600; test++) {
        int offset = offsets[test % 6], count = counts[(test / 6) % 8];
        channel.leftvol = test % 256;
        channel.rightvol = (test * 37) % 256;
        channel.doppler = (test / 48) % 2;
        channel.dopplerScale = test % 3 ? 1.0f : 1.5f;
        channel.oldDopplerScale = channel.dopplerScale;
        snd_vol = test % 256;
        for (i = 0; i < PAINTBUFFER_SIZE; i++) {
            initial[i].left = (int)(randomValue() & 65535) - 32768;
            initial[i].right = (int)(randomValue() & 65535) - 32768;
        }
        memcpy(paintbuffer, initial, sizeof initial);
        toggle.integer = 0;
        S_PaintChannelFrom16_scalar(&channel, &sound, count, offset, 13);
        memcpy(expected, paintbuffer, sizeof expected);
        memcpy(paintbuffer, initial, sizeof initial);
        toggle.integer = 1;
        S_PaintChannelFrom16_scalar(&channel, &sound, count, offset, 13);
        assert(!memcmp(expected, paintbuffer, sizeof expected));
    }
    puts("PASS: scalar mixer output exact across 600 boundary, volume and Doppler cases");
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='q3-mixer-test-') as tmp:
    src = Path(tmp) / 'test.c'
    exe = Path(tmp) / 'test'
    src.write_text(harness)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-O2', '-Wall', '-Wextra',
                    '-Werror', '-fsanitize=address,undefined', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
