//
//  PendulumRenderer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import Metal
import ARHeadsetKit

class AR_MultiPendulumRenderer: MainRenderer {
    override var makeCustomRenderer: CustomRendererInitializer {
        PendulumRenderer.init
    }
}

class PendulumRenderer {
    unowned let renderer: MainRenderer
    var frameUpdateSemaphore = DispatchSemaphore(value: 1)
    
    var numPendulums: Int
    var combinedPendulumLength: Double
    var gravitationalAccelerationHalf: Double
    
    var masses: [Double]
    var lengths: [Double]
    var energy: Double
    
    var shouldResetSimulation = true
    var simulationIsRunning = false
    var isReplaying = false
    
    var lastFrameID = 0
    var frames: [[PendulumState]] = []
    var lastInteractionRay: RayTracing.Ray!
    
    var failed = false
    var failureTrajectory: FailureTrajectory!
    
    var pendulumOrientation: simd_quatf = .init(from: [0, 0, 1], to: normalize([-1, 0, 1]))
    var pendulumHalfWidth: Float = 0.025
    var jointRadius: Float = 0.035
    
    var pendulumLocation: simd_float3 = [0.25, 0, -0.25]
    var pendulumColor: simd_float3 = [0.9, 0.0, 0.0]
    var jointColor: simd_float3    = [0.3, 0.3, 0.3]
    var doingTwoSidedPendulums = true
    
    var shouldUpdateStand = true
    var lastStandState: StandState!
    var standObjects: [ARObject] = []
    var standColor: simd_float3 = [0.5, 0.5, 0.5]
    var pivotColor: simd_float3 = [0.3, 0.3, 0.3]
    
    var prototype: PendulumSimulationPrototype
    var meshConstructor: PendulumMeshConstructor!
    var pendulumInterface: PendulumInterface!
    
    var stateEquations: PendulumStateEquations!
    var timeStepper: PendulumTimeStepper!
    
    required init(renderer: MainRenderer, library: MTLLibrary!) {
        self.renderer = renderer
        
        stateEquations = PendulumStateEquations()
        prototype = PendulumSimulationPrototype()
        
        let configuration = prototype.configuration
        numPendulums = configuration.numPendulums
        combinedPendulumLength = configuration.lengths.reduce(0, +)
        gravitationalAccelerationHalf = configuration.gravitationalAccelerationHalf
        
        (masses, lengths) = (configuration.masses, configuration.lengths)
        
        stateEquations.setSimulation(numPendulums, gravitationalAccelerationHalf,
                                     masses:  configuration.masses,
                                     lengths: configuration.lengths)
        
        var firstStateGroup = [PendulumState.firstState(configuration.initialAngles, configuration.initialAngularVelocities)]
        stateEquations.process(numPendulums, gravitationalAccelerationHalf, state: &firstStateGroup[0])
        
        
        
        energy = firstStateGroup[0].energy
        frames = [firstStateGroup]
        
        timeStepper = .init(pendulumRenderer: self, energy: energy)
        
        meshConstructor = PendulumMeshConstructor(pendulumRenderer: self, library: library)
        meshConstructor.statesToRender = frames[0]
        
        pendulumInterface = PendulumInterface(pendulumRenderer: self, library: library)
    }
}
