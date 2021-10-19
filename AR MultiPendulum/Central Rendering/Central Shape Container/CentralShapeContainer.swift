//
//  CentralShapeContainer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/18/21.
//

import Metal
import simd

protocol CentralShapeContainer {
    var centralRenderer: CentralRenderer { get }
    
    static var shapeType: CentralShapeType { get }
    var sizeRange: [Int] { get }
    var shapes: [CentralShape] { get }
    
    var aliases: [CentralAliasContainer] { get set }
    var numAliases: Int { get set }
    
    var uniformBuffer: MultiLevelBuffer<CentralRenderer.UniformLevel> { get set }
    
    var normalOffset: Int { get }
    var indexOffset: Int { get }
    var geometryBuffer: MTLBuffer { get }
    
    init(centralRenderer: CentralRenderer, range: [Int])
    
    mutating func appendAlias(of object: CentralObject)
    mutating func appendAlias(of object: CentralObject, desiredLOD: Int)
    mutating func appendAlias(of object: CentralObject, desiredLOD: Int, userDistanceEstimate: Float)
}

extension CentralShapeContainer {
    var renderer: Renderer { centralRenderer.renderer }
    var device: MTLDevice { centralRenderer.device }
    var renderIndex: Int { centralRenderer.renderIndex }
    
    var doingMixedRealityRendering: Bool { centralRenderer.doingMixedRealityRendering }
    var shapeContainers: [CentralShapeContainer] { centralRenderer.shapeContainers }
    
    var lodTransform: simd_float4x4 { centralRenderer.lodTransform }
    var lodTransform2: simd_float4x4 { centralRenderer.lodTransform2 }
    var lodTransformInverse: simd_float4x4 { centralRenderer.lodTransformInverse }
    var lodTransformInverse2: simd_float4x4 { centralRenderer.lodTransformInverse2 }
    
    typealias VertexUniforms       = CentralRenderer.VertexUniforms
    typealias MixedRealityUniforms = CentralRenderer.MixedRealityUniforms
    typealias FragmentUniforms     = CentralRenderer.FragmentUniforms
}

struct CentralAliasContainer: ExpressibleByArrayLiteral {
    typealias ArrayLiteralElement = Never
    typealias Alias = CentralObject.Alias
    
    var closeAliases: [Alias]
    var farAliases: [Alias]
    
    var count: Int { closeAliases.count + farAliases.count }
    
    init(arrayLiteral elements: Never...) {
        closeAliases = []
        farAliases = []
    }
    
    mutating func removeAll() {
        closeAliases.removeAll(keepingCapacity: true)
        farAliases.removeAll(keepingCapacity: true)
    }
    
    func forEach(_ body: (CentralObject.Alias) throws -> Void) rethrows {
        try! closeAliases.forEach(body)
        try! farAliases.forEach(body)
    }
    
    mutating func append(_ alias: Alias, userDistance: Float) {
        if userDistance <= 0.15, alias.allowsViewingInside {
            closeAliases.append(alias)
        } else {
            farAliases.append(alias)
        }
    }
}

extension CentralRenderer {
    
    enum UniformLevel: UInt8, MultiLevelBufferLevel {
        case vertex
        case fragment
        
        static var bufferLabel = "Central Shape Uniform Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .vertex:   return capacity * Renderer.numRenderBuffers * MemoryLayout<MixedRealityUniforms>.stride
            case .fragment: return capacity * Renderer.numRenderBuffers * MemoryLayout<FragmentUniforms>.stride
            }
        }
    }
    
    struct ShapeContainer<Shape: CentralShape>: CentralShapeContainer {
        var centralRenderer: CentralRenderer
        
        static var shapeType: CentralShapeType { Shape.shapeType }
        var sizeRange: [Int]
        var shapes: [CentralShape]
        
        var aliases: [CentralAliasContainer]
        var numAliases = 0
        
        var uniformBuffer: MultiLevelBuffer<UniformLevel>
        
        var normalOffset: Int
        var indexOffset: Int
        var geometryBuffer: MTLBuffer
        
        mutating func appendAlias(of object: CentralObject) {
            numAliases += 1
            Shape.appendAlias(of: object, to: &self)
        }
        
        mutating func appendAlias(of object: CentralObject, desiredLOD: Int) {
            numAliases += 1
            Shape.appendAlias(of: object, to: &self, desiredLOD: desiredLOD)
        }
        
        mutating func appendAlias(of object: CentralObject, desiredLOD: Int, userDistanceEstimate: Float) {
            numAliases += 1
            Shape.appendAlias(of: object, to: &self, desiredLOD: desiredLOD, userDistanceEstimate: userDistanceEstimate)
        }
        
        init(centralRenderer: CentralRenderer, range: [Int] = [1]) {
            self.centralRenderer = centralRenderer
            let device = centralRenderer.device
            
            let shapeCapacity = 4
            uniformBuffer = device.makeMultiLevelBuffer(capacity: shapeCapacity, options: [.cpuCacheModeWriteCombined, .storageModeShared])
            
            aliases = Array(repeating: [], count: range.count)
            
            
            
            sizeRange = range
            
            var vertices = [CentralVertex]()
            var indices = [UInt16]()
            
            shapes = range.map {
                 Shape(centralRenderer: centralRenderer, numSegments: UInt16($0), vertices: &vertices, indices: &indices)
            }
            
            (geometryBuffer, normalOffset, indexOffset) = centralRenderer.makeGeometryBuffer(Shape.self, vertices, indices)
            
            debugLabel {
                uniformBuffer .label = "Central \(Shape.shapeType.toString) Uniform Buffer"
                geometryBuffer.label = "Central \(Shape.shapeType.toString) Geometry Buffer"
                
                geometryBuffer.addDebugMarker("Vertices", range: 0..<normalOffset)
                geometryBuffer.addDebugMarker("Normals",  range: normalOffset..<indexOffset)
                geometryBuffer.addDebugMarker("Indices",  range: indexOffset..<geometryBuffer.length)
            }
        }
    }
    
}
