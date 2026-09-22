#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#include <stdio.h>
#include <math.h>
int main(void) {
 CGLPixelFormatAttribute attrs[]={kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};
 CGLPixelFormatObj pix;CGLContextObj ctx;GLint n;GLuint tex,fbo;GLenum status;
 GLfloat result[4],wanted=0.123456789f;
 if(CGLChoosePixelFormat(attrs,&pix,&n)!=kCGLNoError || !pix) return 2;
 if(CGLCreateContext(pix,0,&ctx)!=kCGLNoError) return 3;
 CGLDestroyPixelFormat(pix);CGLSetCurrentContext(ctx);
 glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
 glTexImage2D(GL_TEXTURE_2D,0,GL_INTENSITY32F_ARB,8,8,0,GL_RGBA,GL_FLOAT,0);
 glGenFramebuffersEXT(1,&fbo);glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,fbo);
 glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT,GL_COLOR_ATTACHMENT0_EXT,GL_TEXTURE_2D,tex,0);
 printf("renderer: %s; initial target: 0x%x\n",glGetString(GL_RENDERER),glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT));
 glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F_ARB,8,8,0,GL_RGBA,GL_FLOAT,0);
 status=glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
 if(status!=GL_FRAMEBUFFER_COMPLETE_EXT) return 4;
 glClearColor(wanted,0,0,1);glClear(GL_COLOR_BUFFER_BIT);
 glReadPixels(1,1,1,1,GL_RGBA,GL_FLOAT,result);
 printf("redefined target: 0x%x; red %.9g -> %.9g; GL error 0x%x\n",status,wanted,result[0],glGetError());
 if(fabsf(result[0]-wanted)>0.00000001f) return 5;
 glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,0);glDeleteFramebuffersEXT(1,&fbo);glDeleteTextures(1,&tex);
 CGLSetCurrentContext(0);CGLDestroyContext(ctx);return 0;
}
