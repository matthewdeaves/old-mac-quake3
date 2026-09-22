#!/usr/bin/env python3
"""Exercise actual stage submission against a GL-state recorder."""
from pathlib import Path
import subprocess
import tempfile

source = Path('code/renderer/tr_shade.c').read_text()
def function(name):
    start = source.index('static ', source.index(name) - 30)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

prefix = r'''
#include <assert.h>
#include <string.h>
typedef int qboolean;
enum { CGEN_IDENTITY, CGEN_VERTEX, AGEN_IDENTITY=0, AGEN_SKIP=1, AGEN_VERTEX=2,
 GL_COLOR_ARRAY=1, GL_UNSIGNED_BYTE=2, GL_FLOAT=3, GLHW_PERMEDIA2=4,
 MAX_SHADER_STAGES=4 };
typedef struct {int integer;} cvar_t;
cvar_t cv, prim, light, vertex, ui;
cvar_t *r_constantColor=&cv, *r_primitives=&prim, *r_lightmap=&light,
 *r_vertexLight=&vertex, *r_uiFullScreen=&ui;
typedef struct {void *image[1]; int vertexLightmap, isLightmap;} bundle_t;
typedef struct {int rgbGen, alphaGen, stateBits; bundle_t bundle[2];} shaderStage_t;
typedef struct {int numPasses, fogNum, numIndexes, indexes[3]; shaderStage_t *xstages[4];
 struct {unsigned char colors[3][4]; float texcoords[2][3][2];} svars;} shaderCommands_t;
shaderCommands_t tess;
struct {int hardwareType;} glConfig;
struct {void *whiteImage;} tr;
static int setArraysOnce, colorEnabled, draws;
static const unsigned char *colorPointer;
static unsigned char currentColor[4], recorded[4][3][4];
void qglDisableClientState(int x) {assert(x==GL_COLOR_ARRAY);colorEnabled=0;}
void qglEnableClientState(int x) {assert(x==GL_COLOR_ARRAY);colorEnabled=1;}
void qglColor4f(float a,float b,float c,float d) {
 currentColor[0]=a*255;currentColor[1]=b*255;currentColor[2]=c*255;currentColor[3]=d*255;
}
void qglColorPointer(int n,int type,int stride,void *p) {colorPointer=p;}
void qglTexCoordPointer(int n,int type,int stride,void *p) {}
void GL_Bind(void *p) {}
void R_BindAnimatedImage(bundle_t *p) {}
void GL_State(int s) {}
void ComputeTexCoords(shaderStage_t *p) {}
/* Model the output of ComputeColors, including non-white fallback data. */
void ComputeColors(shaderStage_t *p) {
 for(int i=0;i<3;i++) for(int j=0;j<4;j++)
  tess.svars.colors[i][j]=(p->rgbGen==CGEN_IDENTITY ? 255 : 20+i+j);
 if(p->alphaGen==AGEN_VERTEX || tess.fogNum)
  for(int i=0;i<3;i++) tess.svars.colors[i][3]=42+i;
}
void R_DrawElements(int n,int *indices) {
 for(int i=0;i<3;i++) memcpy(recorded[draws][i],colorEnabled?colorPointer+4*i:currentColor,4);
 draws++;
}
void DrawMultitextured(shaderCommands_t *input,int stage) {R_DrawElements(3,input->indexes);}
'''
main = r'''
int main(void) {
 shaderStage_t stages[2]; unsigned char reference[sizeof recorded]; int count=0;
 memset(stages,0,sizeof stages);
 tess.xstages[0]=&stages[0]; tess.numIndexes=3;
 for(int passes=1;passes<=2;passes++) for(int fog=0;fog<=1;fog++)
 for(int rgb=0;rgb<=1;rgb++) for(int alpha=0;alpha<=2;alpha++)
 for(int multi=0;multi<=1;multi++) for(int primitive=2;primitive<=3;primitive++)
 for(int once=0;once<=1;once++) {
  tess.numPasses=passes;tess.fogNum=fog;prim.integer=primitive;setArraysOnce=once;
  tess.xstages[1]=passes==2?&stages[1]:0;
  stages[0].rgbGen=rgb;stages[0].alphaGen=alpha;
  stages[0].bundle[1].image[0]=multi?(void*)1:0;
  stages[1].rgbGen=CGEN_VERTEX;stages[1].alphaGen=AGEN_VERTEX;
  for(int enabled=0;enabled<=1;enabled++) {
   cv.integer=enabled;colorEnabled=1;colorPointer=&tess.svars.colors[0][0];
   memset(currentColor,17,4);memset(recorded,0,sizeof recorded);draws=0;
   RB_IterateStagesGeneric(&tess);
   if(!enabled) memcpy(reference,recorded,sizeof recorded);
   else assert(!memcmp(reference,recorded,sizeof recorded));
  }
  count++;
 }
 assert(count==192);
 return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    c = Path(tmp)/'test.c'
    c.write_text(prefix + function('RB_ConstantWhiteStage') + '\n' + function('RB_IterateStagesGeneric') + main)
    exe = Path(tmp)/'test'
    subprocess.run(['cc','-std=c99','-fsanitize=address,undefined','-g',str(c),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
print('PASS: constant-color submission matches baseline across 192 stage-state combinations')
