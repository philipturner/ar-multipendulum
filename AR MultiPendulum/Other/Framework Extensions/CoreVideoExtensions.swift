//
//  CoreVideoExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/22/21.
//

import CoreVideo
import Metal

// High-level wrappers around functions bridging between CoreVideo and Metal

enum CV {
    struct MetalTexture {
        private var texture: CVMetalTexture
        var asCVMetalTexture: CVMetalTexture { texture }
        
        init(_ texture: CVMetalTexture) {
            self.texture = texture
        }
        
        static var typeID: CFTypeID { CVMetalTextureGetTypeID() }
        
        func getTexture() -> MTLTexture? {
            CVMetalTextureGetTexture(texture)
        }
        
        var isFlipped: Bool {
            CVMetalTextureIsFlipped(texture)
        }
        
        func getCleanTexCoords(_ lowerLeft: UnsafeMutablePointer<Float>, _ lowerRight: UnsafeMutablePointer<Float>,
                               _ upperRight: UnsafeMutablePointer<Float>, _ upperLeft: UnsafeMutablePointer<Float>) {
            CVMetalTextureGetCleanTexCoords(texture, lowerLeft, lowerRight, upperRight, upperLeft)
        }
    }
}

extension Optional where Wrapped == CVMetalTextureCache {
    
    init(_ allocator: CFAllocator?, _ cacheAttributes: [CFString : Any]?,
         _ metalDevice: MTLDevice, _ textureAttributes: [CFString : Any]?,
         _ returnRef: UnsafeMutablePointer<CVReturn>? = nil)
    {
        var cacheOut: CVMetalTextureCache?
        let output = CVMetalTextureCacheCreate(allocator,   cacheAttributes as CFDictionary?,
                                               metalDevice, textureAttributes as CFDictionary?, &cacheOut)
        
        if let returnRef = returnRef {
            returnRef.pointee = output
        }
        
        self = cacheOut
    }
    
}

extension CVMetalTextureCache {
    
    static var typeID: CFTypeID { CVMetalTextureCacheGetTypeID() }
    
    func createMTLTexture(_ sourceImage: CVImageBuffer, _ pixelFormat: MTLPixelFormat,
                          _ width: Int, _ height: Int, _ planeIndex: Int = 0) -> MTLTexture? {
        createTexture(nil, sourceImage, nil, pixelFormat, width, height, planeIndex)?.getTexture()
    }
    
    func createTexture(_ allocator: CFAllocator?, _ sourceImage: CVImageBuffer,
                       _ textureAttributes: [CFString : Any]?,
                       _ pixelFormat: MTLPixelFormat, _ width: Int, _ height: Int, _ planeIndex: Int,
                       _ returnRef: UnsafeMutablePointer<CVReturn>? = nil) -> CV.MetalTexture?
    {
        var textureOut: CVMetalTexture?
        let output = CVMetalTextureCacheCreateTextureFromImage(allocator, self, sourceImage,
                                                               textureAttributes as CFDictionary?,
                                                               pixelFormat, width, height, planeIndex, &textureOut)
        
        if let returnRef = returnRef {
            returnRef.pointee = output
        }
        
        guard let texture = textureOut else {
            return nil
        }
        
        return CV.MetalTexture(texture)
    }
    
    func flush(_ options: CVOptionFlags) {
        CVMetalTextureCacheFlush(self, options)
    }
    
}
