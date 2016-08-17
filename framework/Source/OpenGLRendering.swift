#if os(Linux)
#if GLES
    import COpenGLES.gles2
    let GL_DEPTH24_STENCIL8 = GL_DEPTH24_STENCIL8_OES
    let GL_TRUE = GLboolean(1)
    let GL_FALSE = GLboolean(0)
#else
    import COpenGL
#endif
#else
#if GLES
    import OpenGLES
#else
    import OpenGL.GL3
#endif
#endif

import Foundation

struct InputTextureProperties {
    let textureCoordinates:[GLfloat]
    let texture:GLuint
}

public struct GLSize {
    public let width:GLint
    public let height:GLint
    
    public init(width:GLint, height:GLint) {
        self.width = width
        self.height = height
    }
    
    public init(_ size:Size) {
        self.width = size.glWidth()
        self.height = size.glHeight()
    }
}

extension Size {
    init(_ size:GLSize) {
        self.width = Float(size.width)
        self.height = Float(size.height)
    }
}

public let standardImageVertices:[GLfloat] = [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0]
public let verticallyInvertedImageVertices:[GLfloat] = [-1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, -1.0]

// "position" and "inputTextureCoordinate", "inputTextureCoordinate2" attribute naming follows the convention of the old GPUImage
func renderQuadWithShader(_ shader:ShaderProgram, uniformSettings:ShaderUniformSettings? = nil, vertices:[GLfloat], inputTextures:[InputTextureProperties]) {
    sharedImageProcessingContext.makeCurrentContext()
    shader.use()
    uniformSettings?.restoreShaderSettings(shader)

    guard let positionAttribute = shader.attributeIndex("position") else { fatalError("A position attribute was missing from the shader program during rendering.") }
    glVertexAttribPointer(positionAttribute, 2, GLenum(GL_FLOAT), 0, 0, vertices)

    for (index, inputTexture) in inputTextures.enumerated() {
        if let textureCoordinateAttribute = shader.attributeIndex("inputTextureCoordinate".withNonZeroSuffix(index)) {
            glVertexAttribPointer(textureCoordinateAttribute, 2, GLenum(GL_FLOAT), 0, 0, inputTexture.textureCoordinates)
        } else if (index == 0) {
            fatalError("The required attribute named inputTextureCoordinate was missing from the shader program during rendering.")
        }
        
        glActiveTexture(textureUnitForIndex(index))
        glBindTexture(GLenum(GL_TEXTURE_2D), inputTexture.texture)

        shader.setValue(GLint(index), forUniform:"inputImageTexture".withNonZeroSuffix(index))
    }
    
    glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
    
    for (index, _) in inputTextures.enumerated() {
        glActiveTexture(textureUnitForIndex(index))
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }
}

public func clearFramebufferWithColor(_ color:Color) {
    glClearColor(GLfloat(color.redComponent), GLfloat(color.greenComponent), GLfloat(color.blueComponent), GLfloat(color.alphaComponent))
    glClear(GLenum(GL_COLOR_BUFFER_BIT))
}

func renderStencilMaskFromFramebuffer(_ framebuffer:Framebuffer) {
    let inputTextureProperties = framebuffer.texturePropertiesForOutputRotation(.noRotation)
    glEnable(GLenum(GL_STENCIL_TEST))
    glClearStencil(0)
    glClear (GLenum(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT))
    glColorMask(GLboolean(GL_FALSE), GLboolean(GL_FALSE), GLboolean(GL_FALSE), GLboolean(GL_FALSE))
    glStencilFunc(GLenum(GL_ALWAYS), 1, 1)
    glStencilOp(GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_REPLACE))
    
#if GL
    glEnable(GLenum(GL_ALPHA_TEST))
    glAlphaFunc(GLenum(GL_NOTEQUAL), 0.0)
    renderQuadWithShader(sharedImageProcessingContext.passthroughShader, vertices:standardImageVertices, inputTextures:[inputTextureProperties])
#else
    let alphaTestShader = crashOnShaderCompileFailure("Stencil"){return try sharedImageProcessingContext.programForVertexShader(OneInputVertexShader, fragmentShader:AlphaTestFragmentShader)}
    renderQuadWithShader(alphaTestShader, vertices:standardImageVertices, inputTextures:[inputTextureProperties])
#endif
    
    glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
    
    glStencilFunc(GLenum(GL_EQUAL), 1, 1)
    glStencilOp(GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_KEEP))
    
#if GL
    glDisable(GLenum(GL_ALPHA_TEST))
#endif
}

func disableStencil() {
    glDisable(GLenum(GL_STENCIL_TEST))
}

func textureUnitForIndex(_ index:Int) -> GLenum {
    switch index {
        case 0: return GLenum(GL_TEXTURE0)
        case 1: return GLenum(GL_TEXTURE1)
        case 2: return GLenum(GL_TEXTURE2)
        case 3: return GLenum(GL_TEXTURE3)
        case 4: return GLenum(GL_TEXTURE4)
        case 5: return GLenum(GL_TEXTURE5)
        case 6: return GLenum(GL_TEXTURE6)
        case 7: return GLenum(GL_TEXTURE7)
        case 8: return GLenum(GL_TEXTURE8)
        default: fatalError("Attempted to address too high a texture unit")
    }
}

func generateTexture(minFilter:Int32, magFilter:Int32, wrapS:Int32, wrapT:Int32) -> GLuint {
    var texture:GLuint = 0
    
    glActiveTexture(GLenum(GL_TEXTURE1))
    glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), minFilter)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), magFilter)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), wrapS)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), wrapT)

    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    
    return texture
}

func generateFramebufferForTexture(_ texture:GLuint, width:GLint, height:GLint, internalFormat:Int32, format:Int32, type:Int32, stencil:Bool) throws -> (GLuint, GLuint?) {
    var framebuffer:GLuint = 0
    glActiveTexture(GLenum(GL_TEXTURE1))

    glGenFramebuffers(1, &framebuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    
    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, internalFormat, width, height, 0, GLenum(format), GLenum(type), nil)
    glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)

    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    if (status != GLenum(GL_FRAMEBUFFER_COMPLETE)) {
        throw FramebufferCreationError(errorCode:status)
    }
    
    let stencilBuffer:GLuint?
    if stencil {
        stencilBuffer = try attachStencilBuffer(width:width, height:height)
    } else {
        stencilBuffer = nil
    }
    
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    return (framebuffer, stencilBuffer)
}

func attachStencilBuffer(width:GLint, height:GLint) throws -> GLuint {
    var stencilBuffer:GLuint = 0
    glGenRenderbuffers(1, &stencilBuffer);
    glBindRenderbuffer(GLenum(GL_RENDERBUFFER), stencilBuffer)
    glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH24_STENCIL8), width, height) // iOS seems to only support combination depth + stencil, from references
#if os(iOS)
    glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_RENDERBUFFER), stencilBuffer)
#endif
    glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_STENCIL_ATTACHMENT), GLenum(GL_RENDERBUFFER), stencilBuffer)

    glBindRenderbuffer(GLenum(GL_RENDERBUFFER), 0)
    
    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    if (status != GLenum(GL_FRAMEBUFFER_COMPLETE)) {
        throw FramebufferCreationError(errorCode:status)
    }
    
    return stencilBuffer
}

extension String {
    func withNonZeroSuffix(_ suffix:Int) -> String {
        if suffix == 0 {
            return self
        } else {
            return "\(self)\(suffix + 1)"
        }
    }
    
    func withGLChar(_ operation:(UnsafePointer<GLchar>) -> ()) {
#if os(Linux)
        // cStringUsingEncoding isn't yet defined in the Linux Foundation.
        // This approach is roughly 35X slower than the cStringUsingEncoding one.
        let bufferCString = UnsafeMutablePointer<UInt8>.allocate(capacity:self.characters.count+1)
        for (index, characterValue) in self.utf8.enumerate() {
            bufferCString[index] = characterValue
        }
        bufferCString[self.characters.count] = 0 // Have to add a null termination
        
        operation(UnsafePointer<GLchar>(bufferCString))
        
        bufferCString.deallocate(capacity:self.characters.count)
#else
        if let value = self.cString(using:String.Encoding.utf8) {
            operation(UnsafePointer<GLchar>(value))
        } else {
            fatalError("Could not convert this string to UTF8: \(self)")
        }
#endif
    }
}

