//
//  Coordinator.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import MetalKit
import ARKit

final class Coordinator: NSObject, MTKViewDelegate, ARSessionDelegate, ObservableObject {
    @Published var settingsIconIsHidden: Bool = false
    @Published var settingsAreShown: Bool = false
    
    var shouldImmediatelyHideSettingsIcon: Bool = false
    
    @Published var renderingSettings: RenderingSettings!
    @Published var interactionSettings: InteractionSettings!
    @Published var lidarEnabledSettings: LiDAREnabledSettings!
    
    @Published var caseSize: LensDistortionCorrector.StoredSettings.CaseSize = .small
    
    @Published var showingAppTutorial: Bool = false
    @Published var settingsShouldBeAnimated: Bool = false
    
    var session: ARSession!
    var view: MTKView!
    var renderer: Renderer!
    private var gestureRecognizer: UILongPressGestureRecognizer!
    
    var separatorView: UIView!
    private var separatorGestureRecognizer: UILongPressGestureRecognizer!
    
    override init() {
        super.init()
        session = ARSession()
        session.delegate = self
        
        let configuration = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            configuration.frameSemantics.insert(.sceneDepth)
            configuration.frameSemantics.insert(.personSegmentation)
        }
        
        session.run(configuration)
        
        view = MTKView()
        
        let nativeBounds = UIScreen.main.nativeBounds
        view.drawableSize = .init(width: nativeBounds.height, height: nativeBounds.width)
        view.autoResizeDrawable = false
        (view.layer as! CAMetalLayer).framebufferOnly = false
        
        view.device = MTLCreateSystemDefaultDevice()!
        view.colorPixelFormat = .bgr10_xr
        view.delegate = self
        
        renderer = Renderer(session: session, view: view, coordinator: self)
        
        
        
        var storedSettings: UserSettings.StoredSettings {
            renderer.userSettings.storedSettings
        }
        
        renderingSettings = .init(storedSettings)
        interactionSettings = .init(storedSettings)
        lidarEnabledSettings = .init(storedSettings)
        
        caseSize = renderer.userSettings.lensDistortionCorrector.storedSettings.caseSize
        
        if storedSettings.isFirstAppLaunch {
            renderer.userSettings.storedSettings.isFirstAppLaunch = false
            showingAppTutorial = true
            
            renderer.showingFirstAppTutorial = true
        }
        
        func makeGestureRecognizer() -> UILongPressGestureRecognizer {
            let output = UILongPressGestureRecognizer()
            output.allowableMovement = .greatestFiniteMagnitude
            output.minimumPressDuration = 0
            return output
        }
        
        gestureRecognizer = makeGestureRecognizer()
        view.addGestureRecognizer(gestureRecognizer)
        
        separatorGestureRecognizer = makeGestureRecognizer()
        separatorView = MRViewSeparator.separatorView
        separatorView.addGestureRecognizer(separatorGestureRecognizer)
        
        DispatchQueue.global(qos: .background).async { [session] in
            while true {
                usleep(5_000_000)
                
                if let frame = session!.currentFrame,
                   let cameraGrainTexture = frame.cameraGrainTexture {
                    cameraGrainTexture.setPurgeableState(.empty)
                    return
                }
            }
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        if gestureRecognizer.state != .possible || separatorGestureRecognizer.state != .possible {
            renderer.pendingTap = .init()
            
            if interactionSettings.canHideSettingsIcon, !settingsIconIsHidden, !settingsAreShown {
                settingsIconIsHidden = true
            }
        }
        
        renderer.update()
    }
}
