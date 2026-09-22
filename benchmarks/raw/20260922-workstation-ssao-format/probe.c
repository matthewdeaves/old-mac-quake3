#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#include <stdio.h>
int main(void) {
 CGLPixelFormatAttribute attrs[]={kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};
 CGLPixelFormatObj pix; CGLContextObj ctx; GLint n;
 if(CGLChoosePixelFormat(attrs,&pix,&n)!=kCGLNoError || !pix) return 2;
 if(CGLCreateContext(pix,0,&ctx)!=kCGLNoError) return 3;
 CGLDestroyPixelFormat(pix); CGLSetCurrentContext(ctx);
 GLenum formats[]={GL_INTENSITY32F_ARB,GL_RGBA32F_ARB,GL_RGBA16F_ARB};
 printf("renderer: %s\n",glGetString(GL_RENDERER));
 for(int i=0;i<3;i++) {
  GLuint tex,fbo; glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D,0,formats[i],8,8,0,GL_RGBA,GL_FLOAT,0);
  glGenFramebuffersEXT(1,&fbo);glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,fbo);
  glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT,GL_COLOR_ATTACHMENT0_EXT,GL_TEXTURE_2D,tex,0);
  printf("format 0x%x: FBO 0x%x GL error 0x%x\n",formats[i],glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT),glGetError());
  glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,0);glDeleteFramebuffersEXT(1,&fbo);glDeleteTextures(1,&tex);
 }
 CGLSetCurrentContext(0);CGLDestroyContext(ctx);return 0;
}
