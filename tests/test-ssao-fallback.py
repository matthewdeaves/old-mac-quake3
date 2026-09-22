#!/usr/bin/env python3
"""Compile the actual SSAO FBO initialization branch against failure injection."""
from pathlib import Path
import subprocess
import tempfile
source=Path('code/rend2/tr_fbo.c').read_text()
start=source.index('\tif (r_ssao->integer)\n\t{')
end=source.index('\n\tGL_CheckErrors();',start)
branch=source[start:end]
code=r'''
#include <assert.h>
#include <stddef.h>
#include <stdarg.h>
#include <string.h>
enum { PRINT_ALL,PRINT_WARNING,GL_TEXTURE_2D,GL_RGBA32F_ARB,GL_RGBA,GL_FLOAT };
typedef struct {int integer;} cv_t; cv_t cv={1};cv_t *r_ssao=&cv;
typedef struct {int width,height,internalFormat;} image_t;
typedef struct {int id;} FBO_t;
image_t depth={8,8,0},screen={4,4,0};FBO_t fbos[2];
struct {FBO_t *hdrDepthFbo,*screenSsaoFbo;image_t *hdrDepthImage,*screenSsaoImage;} tr;
static int failFirst,failRetry,failOutput,checks,uploads,outputCreated;
static void print(int level,const char *fmt,...) {}
static void set(const char *name,const char *value) {
 assert(!strcmp(name,"r_ssao"));assert(!strcmp(value,"0"));cv.integer=0;
}
struct {void(*Printf)(int,const char*,...);void(*Cvar_Set)(const char*,const char*);}ri={print,set};
FBO_t *FBO_Create(const char *name,int width,int height) {
 if(!strcmp(name,"_hdrDepth")) return &fbos[0];
 assert(!strcmp(name,"_screenssao"));outputCreated++;return &fbos[1];
}
void FBO_Bind(FBO_t *fbo) {}
void FBO_AttachTextureImage(image_t *image,int index) {}
int R_CheckFBO(FBO_t *fbo) {
 if(fbo==&fbos[1]) return !failOutput;
 checks++;return checks==1 ? !failFirst : !failRetry;
}
void GL_BindToTMU(image_t *image,int unit) {assert(image==&depth);assert(unit==0);}
void qglTexImage2D(int target,int level,int internal,int width,int height,int border,int format,int type,const void *data) {
 assert(internal==GL_RGBA32F_ARB && width==8 && height==8);
 assert(format==GL_RGBA && type==GL_FLOAT && data==NULL);uploads++;
}
void initialize(void) {
''' + branch + r'''
}
int main(void) {
 tr.hdrDepthImage=&depth;tr.screenSsaoImage=&screen;
 for(int a=0;a<2;a++)for(int b=0;b<2;b++)for(int c=0;c<2;c++) {
  failFirst=a;failRetry=b;failOutput=c;
  cv.integer=1;checks=uploads=outputCreated=0;depth.internalFormat=0;
  initialize();
  assert(uploads==a);assert(checks==1+a);
  assert(outputCreated==!(a&&b));
  assert(cv.integer==(!(a&&b)&&!c));
  if(a)assert(depth.internalFormat==GL_RGBA32F_ARB);
 }
 cv.integer=0;checks=uploads=outputCreated=0;initialize();
 assert(!checks&&!uploads&&!outputCreated);
 return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'test.c';p.write_text(code);exe=Path(tmp)/'test'
    subprocess.run(['cc','-std=c99','-fsanitize=address,undefined',str(p),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
print('PASS: SSAO retries RGBA32F and disables incomplete targets')
