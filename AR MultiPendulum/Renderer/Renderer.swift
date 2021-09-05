//
//  Renderer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import MetalKit
import ARKit

final class Renderer {
    var session: ARSession
    var view: MTKView
    var coordinator: Coordinator
    
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var library: MTLLibrary
    
    static let numRenderBuffers = 3
    
    var frameIndex: Int = 0
    var renderIndex: Int = -1
    var renderSemaphore = DispatchSemaphore(value: numRenderBuffers)
    
    var usingVertexAmplification: Bool
    var usingLiDAR: Bool
    
    struct Tap { }
    
    var pendingTap: Tap!
    var tapAlreadyStarted = false
    var timeSinceLastTap: Int = 200_000_000
    var timeSinceCurrentTap: Int = 100_000_000
    var lastTapDirectionWasSwitch = false
    
    var timeSinceSettingsOpenAnimationStart = Int.min
    var shouldRenderToDisplay = true
    var showingFirstAppTutorial = false
    
    var doingMixedRealityRendering = false
    var usingModifiedPerspective = false
    var alreadyStartedUsingModifiedPerspective = false
    var flyingDirectionIsForward = true
    
    var allowingSceneReconstruction = true
    var allowingHandReconstruction = true
    var allowingFaceTracking = true
    
    var ambientLightColor: simd_half3!
    var directionalLightColor: simd_half3!
    var lightDirection = simd_half3(simd_float3(0, 1, 0))
    
    var cameraMeasurements: CameraMeasurements { userSettings.cameraMeasurements }
    var interactionRay: RayTracing.Ray?
    
    var colorTextureY: MTLTexture!
    var colorTextureCbCr: MTLTexture!
    var sceneDepthTexture: MTLTexture!
    var segmentationTexture: MTLTexture!
    var textureCache: CVMetalTextureCache
    
    var msaaTexture: MTLTexture
    var depthStencilTexture: MTLTexture
    var depthStencilState: MTLDepthStencilState
    
    var userSettings: UserSettings!
    var handRenderer: HandRenderer!
    var handRenderer2D: HandRenderer2D!
    var pendulumRenderer: PendulumRenderer!
    
    var sceneRenderer: SceneRenderer!
    var sceneRenderer2D: SceneRenderer2D!
    var interfaceRenderer: InterfaceRenderer!
    var centralRenderer: CentralRenderer!
    
    init(session: ARSession, view: MTKView, coordinator: Coordinator) {
        self.session = session
        self.view = view
        self.coordinator = coordinator
        
        device = view.device!
        commandQueue = device.makeCommandQueue()!
        commandQueue.optLabel = "Command Queue"
        
        // Not using vertex amplification on A13 GPUs because they don't support
        // MSAA with layered rendering. Vertex amplification can still be used
        // with viewports instead of layers, but viewports don't work with VRR and
        // have significantly worse rendering performance than using layers.
        
        usingVertexAmplification = device.supportsFamily(.apple7)
        usingLiDAR = !coordinator.disablingLiDAR && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        
        textureCache = CVMetalTextureCache?(nil,    [kCVMetalTextureCacheMaximumTextureAgeKey : 1e-5],
                                            device, [kCVMetalTextureUsage : MTLTextureUsage.shaderRead.rawValue])!
        
        
        
        let textureDescriptor = MTLTextureDescriptor()
        let bounds = UIScreen.main.nativeBounds
        textureDescriptor.width  = Int(bounds.height)
        textureDescriptor.height = Int(bounds.width)
        
        textureDescriptor.usage = .renderTarget
        textureDescriptor.textureType = .type2DMultisample
        textureDescriptor.storageMode = .memoryless
        textureDescriptor.sampleCount = 4
        
        textureDescriptor.pixelFormat = view.colorPixelFormat
        msaaTexture = device.makeTexture(descriptor: textureDescriptor)!
        msaaTexture.optLabel = "MSAA Texture"
        
        textureDescriptor.pixelFormat = .depth32Float_stencil8
        depthStencilTexture = device.makeTexture(descriptor: textureDescriptor)!
        depthStencilTexture.optLabel = "Depth-Stencil Texture"
        
        // Convential projection transforms map the vast majority of depth values
        // to the range (0.99, 1.00), drastically lowering depth precision for the
        // majority of any rendered scene and making z-fighting happen in some situations
        // situations just because an object is far away. This problem is often mitigated
        // by fine-tuning the near and far planes of a projection matrix, reducing
        // the dynamic range of the near and far clip planes.
        //
        // However, there is a more correct approach that allows extremely close and far
        // clip planes by undoing the loss in depth precision. Transforming depths by
        // subtracting them from one means the majority of depths fall in (0.00, 0.01).
        // When using a floating-point number instead of a normalized integer to store depth,
        // the high dynamic range of floating-point numbers means depths have much greater
        // precision when closer to zero.
        //
        // This solution is implemented by flipping the near and far planes in
        // the projection matrix. It also requires changing the depth compare mode
        // from "less" to "greater" and vice versa.
        //
        // NOTE: This approach only improves precision when using floating-point
        // depth formats. It does not affect precision of normalized integer depth formats.
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .greater
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.optLabel = "Render Depth-Stencil State"
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        
        
        library = device.makeDefaultLibrary()!
        
        let initializationSemaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if usingLiDAR {
                sceneRenderer = SceneRenderer(renderer: self, library: library)
            }
            
            sceneRenderer2D = SceneRenderer2D(renderer: self, library: library)
            
            initializationSemaphore.signal()
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            userSettings     = UserSettings    (renderer: self, library: library)
            pendulumRenderer = PendulumRenderer(renderer: self, library: library)
            centralRenderer  = CentralRenderer (renderer: self, library: library)
            
            if usingLiDAR {
                handRenderer = HandRenderer(renderer: self, library: library)
            }
            
            handRenderer2D = HandRenderer2D(renderer: self, library: library)
            
            initializationSemaphore.signal()
        }
        
        interfaceRenderer = InterfaceRenderer(renderer: self, library: library)
        
        initializationSemaphore.wait()
        initializationSemaphore.wait()
    }
}

protocol DelegateRenderer {
    var renderer: Renderer { get }
    init(renderer: Renderer, library: MTLLibrary)
}

extension DelegateRenderer {
    var device: MTLDevice { renderer.device }
    var renderIndex: Int { renderer.renderIndex }
    var usingVertexAmplification: Bool { renderer.usingVertexAmplification }
    var usingLiDAR: Bool { renderer.usingLiDAR }
    
    var shouldRenderToDisplay: Bool { renderer.shouldRenderToDisplay }
    var doingMixedRealityRendering: Bool { renderer.doingMixedRealityRendering }
    var usingModifiedPerspective: Bool { renderer.usingModifiedPerspective }
    
    var leftEyePosition: simd_float3 { renderer.cameraMeasurements.leftEyePosition }
    var rightEyePosition: simd_float3 { renderer.cameraMeasurements.rightEyePosition }
    var handheldEyePosition: simd_float3 { renderer.cameraMeasurements.handheldEyePosition }
    
    var ambientLightColor: simd_half3 { renderer.ambientLightColor }
    var directionalLightColor: simd_half3 { renderer.directionalLightColor }
    var lightDirection: simd_half3 { renderer.lightDirection }
    
    var colorTextureY: MTLTexture! { renderer.colorTextureY }
    var colorTextureCbCr: MTLTexture! { renderer.colorTextureCbCr }
    var sceneDepthTexture: MTLTexture! { renderer.sceneDepthTexture }
    var segmentationTexture: MTLTexture! { renderer.segmentationTexture }
    
    var interfaceRenderer: InterfaceRenderer { renderer.interfaceRenderer }
    var centralRenderer: CentralRenderer { renderer.centralRenderer }
}

extension DelegateRenderer {
    var imageResolution: CGSize { renderer.cameraMeasurements.imageResolution }
    
    var cameraToWorldTransform: simd_float4x4 { renderer.cameraMeasurements.cameraToWorldTransform }
    var worldToCameraTransform: simd_float4x4 { renderer.cameraMeasurements.worldToCameraTransform }
    var modifiedPerspectiveToWorldTransform: simd_float4x4 { renderer.cameraMeasurements.modifiedPerspectiveToWorldTransform }
    var worldToModifiedPerspectiveTransform: simd_float4x4 { renderer.cameraMeasurements.worldToModifiedPerspectiveTransform }
    
    var worldToScreenClipTransform: simd_float4x4 { renderer.cameraMeasurements.worldToScreenClipTransform }
    var worldToMixedRealityCullTransform: simd_float4x4 { renderer.cameraMeasurements.worldToMixedRealityCullTransform }
    var worldToLeftClipTransform: simd_float4x4 { renderer.cameraMeasurements.worldToLeftClipTransform }
    var worldToRightClipTransform: simd_float4x4 { renderer.cameraMeasurements.worldToRightClipTransform }
    
    var cameraSpaceLeftEyePosition: simd_float3 { renderer.cameraMeasurements.cameraSpaceLeftEyePosition }
    var cameraSpaceRightEyePosition: simd_float3 { renderer.cameraMeasurements.cameraSpaceRightEyePosition }
    var cameraSpaceMixedRealityCullOrigin: simd_float3 { renderer.cameraMeasurements.cameraSpaceMixedRealityCullOrigin }
    
    var cameraToLeftClipTransform: simd_float4x4 { renderer.cameraMeasurements.cameraToLeftClipTransform }
    var cameraToRightClipTransform: simd_float4x4 { renderer.cameraMeasurements.cameraToRightClipTransform }
    var cameraToMixedRealityCullTransform: simd_float4x4 { renderer.cameraMeasurements.cameraToMixedRealityCullTransform }
}
