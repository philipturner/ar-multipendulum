//
//  PendulumRendererExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import Metal
import simd

extension PendulumRenderer: GeometryRenderer {
    
    func updateResources() {
        doingTwoSidedPendulums = renderer.userSettings.storedSettings.doingTwoSidedPendulums
        
        var modifiedState: PendulumState?
        let interactionRay = renderer.interactionRay
        
        @inline(__always)
        func highlightSimulation() {
            pendulumColor = [1.0, 0.25, 0.25]
            jointColor    = [0.5, 0.5, 0.5]
            
            standColor = [0.8, 0.8, 0.8]
            pivotColor = [0.6, 0.6, 0.6]
        }
        
        @inline(__always)
        func unhighlightSimulation() {
            pendulumColor = [0.9, 0.0, 0.0]
            jointColor    = [0.3, 0.3, 0.3]
            
            standColor = [0.5, 0.5, 0.5]
            pivotColor = [0.3, 0.3, 0.3]
        }
        
        switch pendulumInterface.currentAction {
        case .movingSimulation(false):
            if let interactionRay = interactionRay {
                let direction2D = normalize(.init(-interactionRay.direction.x, -interactionRay.direction.z))
                
                if any(abs(direction2D) .> 1e-8) {
                    pendulumOrientation = .init(from: [0, 0, 1], to: .init(direction2D[0], 0, direction2D[1]))
                    pendulumLocation = fma(normalize(interactionRay.direction), 0.5, interactionRay.origin)
                }
            }
            
            highlightSimulation()
        case .modifyingSimulation(let originalRay, let originalDirection, let wasReplaying, let stateToModify):
            isReplaying = false
            
            if let interactionRay = interactionRay, interactionRay != originalRay, interactionRay != lastInteractionRay {
                let pendulumPlane = RayTracing.Plane(point: pendulumLocation, normal: pendulumOrientation.act([0, 0, 1]))
                let newIntersection = RayTracing.project(interactionRay, onto: pendulumPlane)
                var newDelta = newIntersection - pendulumLocation
                
                let zAxis = pendulumOrientation.act([0, 0, 1])
                newDelta -= dot(newDelta, zAxis) * zAxis
                
                lastInteractionRay = interactionRay
                
                if any(abs(newDelta) .> 1e-8) {
                    let newDirection = normalize(newDelta)
                    let rotation = simd_quatf(from: originalDirection, to: newDirection)
                    
                    var angle = rotation.angle
                    angle = copysign(angle, dot(rotation.axis, zAxis))
                    
                    modifiedState = stateToModify
                    modifiedState!.changeAngles(by: Double(angle))
                }
            }
            
            if renderer.pendingTap == nil {
                isReplaying = wasReplaying
                pendulumInterface.currentAction = .none
                
                unhighlightSimulation()
            } else {
                highlightSimulation()
            }
        default:
            unhighlightSimulation()
        }
        
        lastInteractionRay = interactionRay
        
        if prototype.shouldResetSimulation || modifiedState != nil {
            prototype.shouldResetSimulation = false
            shouldResetSimulation = true
            
            var configuration = prototype.configuration
            numPendulums = configuration.numPendulums
            combinedPendulumLength = configuration.lengths.reduce(0, +)
            gravitationalAccelerationHalf = configuration.gravitationalAccelerationHalf
            
            (masses, lengths) = (configuration.masses, configuration.lengths)
            
            if let modifiedState = modifiedState {
                configuration.initialAngles = modifiedState.angles
                configuration.initialAngularVelocities = modifiedState.angularVelocities
            } else {
                isReplaying = false
            }
            
            var firstStateGroup = [PendulumState.firstState(configuration.initialAngles, configuration.initialAngularVelocities)]
            PendulumStateEquations.solveCoords(numPendulums, lengths: lengths, state: &firstStateGroup[0])
            
            
            
            frameUpdateSemaphore.wait()
            
            frames = [firstStateGroup]
            lastFrameID = 0
            failed = false
            failureTrajectory = nil
        } else {
            frameUpdateSemaphore.wait()
        }
        
        var shouldRenderTrajectory = false
        
        if frames.count > lastFrameID + 1 {
            if isReplaying {
                lastFrameID += 1
                meshConstructor.statesToRender = frames[lastFrameID]
            } else {
                meshConstructor.statesToRender = [frames[lastFrameID].last!]
            }
        } else {
            if failed {
                lastFrameID += 1
                shouldRenderTrajectory = true
                
                meshConstructor.statesToRender = nil
            } else {
                meshConstructor.statesToRender = [frames.last!.last!]
            }
        }
        
        frameUpdateSemaphore.signal()
        
        if shouldResetSimulation, !simulationIsRunning {
            shouldResetSimulation = false
            
            self.simulationIsRunning = true
            resumeSimulation()
        }
        
        
        
        if shouldRenderTrajectory {
            failureTrajectory.updateObjects(pendulumRenderer: self, frameID: lastFrameID)
            
            centralRenderer.append(objects: &failureTrajectory.jointObjects, desiredLOD: 64)
            centralRenderer.append(objects: &failureTrajectory.rectangleObjects)
        }
        
        
        pendulumInterface.updateResources()
        
        createStandObjects()
        centralRenderer.append(objects: &standObjects)
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        meshConstructor.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
    }
    
}

extension PendulumRenderer {
    
    func resumeSimulation() {
        let numPendulums = self.numPendulums
        let gravitationalAccelerationHalf = self.gravitationalAccelerationHalf
        
        let masses = self.masses
        let lengths = self.lengths
        
        var lastState = frames.last!.last!
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var failed = false
            
            if lastState.energy == nil {
                stateEquations.setSimulation(numPendulums, gravitationalAccelerationHalf,
                                             masses: masses, lengths: lengths)
                
                stateEquations.process(numPendulums, gravitationalAccelerationHalf, state: &lastState)
                energy = lastState.energy
                
                timeStepper.reset(pendulumRenderer: self, energy: energy)
            }
            
            while true {
                var nextStates: [PendulumState]
                var failureTrajectory: FailureTrajectory!
                
                do {
                    nextStates = try timeStepper.createFrame(lastState: lastState, failed: &failed)
                } catch {
                    simulationIsRunning = false
                    return
                }
                
                if failed {
                    failureTrajectory = .init(state: lastState, lengths: lengths,
                                              gravityHalf: gravitationalAccelerationHalf)
                }
                
                while true {
                    frameUpdateSemaphore.wait()
                    
                    if shouldResetSimulation || failed {
                        if failed {
                            self.failed = true
                            self.failureTrajectory = failureTrajectory!
                        }
                        
                        simulationIsRunning = false
                        
                        frameUpdateSemaphore.signal()
                        return
                    }
                    
                    if frames.count > lastFrameID + 300 {
                        frameUpdateSemaphore.signal()
                        usleep(8333)
                    } else {
                        frames.append(nextStates)
                        frameUpdateSemaphore.signal()
                        
                        lastState = nextStates.last!
                        break
                    }
                }
            }
        }
    }
    
}
