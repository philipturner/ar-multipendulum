//
//  MultiLevelBuffer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/2/21.
//

import Metal
import simd

protocol MultiLevelBufferLevel: CaseIterable {
    var rawValue: UInt8 { get }
    init?(rawValue: UInt8)
    
    static var bufferLabel: String { get }
    func getSize(capacity: Int) -> Int
}

extension MultiLevelBufferLevel {
    static var numCases: Int { Self.allCases.count}
}

struct MultiLevelBuffer<LevelType: MultiLevelBufferLevel> {
    private(set) var capacity: Int
    private var offsets: [Int]
    private(set) var buffer: MTLBuffer
    
    var label: String? {
        get { buffer.label }
        nonmutating set { buffer.label = newValue }
    }
    
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        nonmutating set { debugLabel { label = newValue } }
    }
    
    var length: Int {
        return buffer.length
    }
    
    fileprivate init(device: MTLDevice, capacity: Int, options: MTLResourceOptions) {
        self.capacity = capacity
        
        offsets = []
        offsets.reserveCapacity(LevelType.numCases)
        
        var size = 0
        
        for level in LevelType.allCases {
            offsets.append(size)
            size += level.getSize(capacity: capacity)
        }
        
        buffer = device.makeBuffer(length: size, options: options)!
        buffer.optLabel = LevelType.bufferLabel
        
        debugLabel {
            var start = offsets[0]
            
            for i in 1...LevelType.numCases {
                let end = (i == LevelType.numCases) ? size : offsets[i]
                let marker = String(describing: LevelType(rawValue: UInt8(i - 1))!)
                
                buffer.addDebugMarker(marker, range: start..<end)
                
                start = end
            }
        }
    }
    
    func offset(for level: LevelType) -> Int {
        offsets[Int(level.rawValue)]
    }
    
    subscript(level: LevelType) -> UnsafeMutableRawPointer {
        buffer.contents() + offset(for: level)
    }
    
    mutating func ensureCapacity(device: MTLDevice, capacity: Int) {
        guard self.capacity < capacity else {
            return
        }
        
        expandCapacity(device: device, capacity: capacity)
    }
    
    mutating func expandCapacity(device: MTLDevice, capacity: Int) {
        self.capacity = capacity
        
        var size = 0
        
        for level in LevelType.allCases {
            offsets[Int(level.rawValue)] = size
            size += level.getSize(capacity: capacity)
        }
        
        let oldLabel = optLabel
        buffer = device.makeBuffer(length: size, options: buffer.resourceOptions)!
        buffer.optLabel = oldLabel
        
        debugLabel {
            var start = offsets[0]
            
            for i in 1...LevelType.numCases {
                let end = (i == LevelType.numCases) ? size : offsets[i]
                let marker = String(describing: LevelType(rawValue: UInt8(i - 1))!)
                
                buffer.addDebugMarker(marker, range: start..<end)
                
                start = end
            }
        }
    }
    
    func makeTexture(descriptor: MTLTextureDescriptor, level: LevelType, offset: Int = 0, bytesPerRow: Int) -> MTLTexture {
        buffer.makeTexture(descriptor: descriptor, offset: self.offset(for: level) + offset, bytesPerRow: bytesPerRow)!
    }
    
    // Compute commands
    
    fileprivate func bindSelf(to encoder: MTLComputeCommandEncoder, level: LevelType,
                              offset: Int, index: Int, asOffset: Bool) {
        if asOffset {
            encoder.setBufferOffset(self.offset(for: level) + offset, index: index)
        } else {
            encoder.setBuffer(buffer, offset: self.offset(for: level) + offset, index: index)
        }
    }
    
    fileprivate func bindSelfForDispatchThreadgroups(to encoder: MTLComputeCommandEncoder, level: LevelType,
                                                     offset: Int, threadsPerThreadgroup: MTLSize) {
        encoder.dispatchThreadgroups(indirectBuffer: buffer, indirectBufferOffset: self.offset(for: level) + offset,
                                     threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    fileprivate func bindSelf(to command: MTLIndirectComputeCommand, level: LevelType,
                              offset: Int, index: Int)
    {
        command.setKernelBuffer(buffer, offset: self.offset(for: level) + offset, at: index)
    }
    
    // Render commands
    
    fileprivate func bindSelfForVertex(to encoder: MTLRenderCommandEncoder, level: LevelType,
                                       offset: Int, index: Int, asOffset: Bool) {
        if asOffset {
            encoder.setVertexBufferOffset(self.offset(for: level) + offset, index: index)
        } else {
            encoder.setVertexBuffer(buffer, offset: self.offset(for: level) + offset, index: index)
        }
    }
    
    fileprivate func bindSelfForVertex(to command: MTLIndirectRenderCommand, level: LevelType,
                                       offset: Int, index: Int)
    {
        command.setVertexBuffer(buffer, offset: self.offset(for: level) + offset, at: index)
    }
    
    fileprivate func bindSelfForFragment(to encoder: MTLRenderCommandEncoder, level: LevelType,
                                         offset: Int, index: Int, asOffset: Bool) {
        if asOffset {
            encoder.setFragmentBufferOffset(self.offset(for: level) + offset, index: index)
        } else {
            encoder.setFragmentBuffer(buffer, offset: self.offset(for: level) + offset, index: index)
        }
    }
    
    fileprivate func bindSelfForFragment(to command: MTLIndirectRenderCommand, level: LevelType,
                                       offset: Int, index: Int)
    {
        command.setFragmentBuffer(buffer, offset: self.offset(for: level) + offset, at: index)
    }
    
    fileprivate func bindSelfForDrawPrimitives(to encoder: MTLRenderCommandEncoder, level: LevelType,
                                               type: MTLPrimitiveType, offset: Int) {
        encoder.drawPrimitives(type: type, indirectBuffer: buffer, indirectBufferOffset: self.offset(for: level) + offset)
    }
    
    fileprivate func bindSelfForDrawIndexedPrimitives(to encoder: MTLRenderCommandEncoder, level: LevelType,
                                                      type: MTLPrimitiveType, indexType: MTLIndexType,
                                                      indexBuffer: MTLBuffer, indexBufferOffset: Int, offset: Int)
    {
        encoder.drawIndexedPrimitives(type:           type,        indexType:            indexType,
                                      indexBuffer:    indexBuffer, indexBufferOffset:    indexBufferOffset,
                                      indirectBuffer: buffer,      indirectBufferOffset: self.offset(for: level) + offset)
    }
    
    // Blit commands
    
    fileprivate func fillSelf(with encoder: MTLBlitCommandEncoder, level: LevelType, range: Range<Int>, value: UInt8) {
        let levelOffset = offset(for: level)
        let fillStart = levelOffset + range.startIndex
        let fillEnd   = levelOffset + range.endIndex
        
        encoder.fill(buffer: buffer, range: fillStart..<fillEnd, value: value)
    }
    
    // Other
    
    fileprivate func copyVRRMap(vrrMap: MTLRasterizationRateMap, level: LevelType, offset: Int) {
        vrrMap.copyParameterData(buffer: buffer, offset: self.offset(for: level) + offset)
    }
}

// Metal extensions

extension MTLDevice {

    func makeMultiLevelBuffer<Level: MultiLevelBufferLevel>(
        capacity: Int, options: MTLResourceOptions = .storageModePrivate) -> MultiLevelBuffer<Level>
    {
        .init(device:   self,
              capacity: capacity,
              options:  options)
    }
    
}

extension MTLComputeCommandEncoder {
    
    func setBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                 offset: Int = 0, index: Int, asOffset: Bool = false) {
        buffer.bindSelf(to:       self,
                        level:    level,
                        offset:   offset,
                        index:    index,
                        asOffset: asOffset)
    }
    
    func dispatchThreadgroups<Level: MultiLevelBufferLevel>(indirectBuffer: MultiLevelBuffer<Level>, indirectBufferLevel: Level,
                                                            indirectBufferOffset: Int = 0, threadsPerThreadgroup: MTLSize)
    {
        indirectBuffer.bindSelfForDispatchThreadgroups(to:                    self,
                                                       level:                 indirectBufferLevel,
                                                       offset:                indirectBufferOffset,
                                                       threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
}

extension MTLIndirectComputeCommand {
    
    func setKernelBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                       offset: Int = 0, at index: Int) {
        buffer.bindSelf(to:     self,
                        level:  level,
                        offset: offset,
                        index:  index)
    }
    
}

extension MTLRenderCommandEncoder {
    
    func setVertexBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                       offset: Int = 0, index: Int, asOffset: Bool = false) {
        buffer.bindSelfForVertex(to:       self,
                                 level:    level,
                                 offset:   offset,
                                 index:    index,
                                 asOffset: asOffset)
    }
    
    func setFragmentBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                         offset: Int = 0, index: Int, asOffset: Bool = false) {
        buffer.bindSelfForFragment(to:       self,
                                   level:    level,
                                   offset:   offset,
                                   index:    index,
                                   asOffset: asOffset)
    }
    
    func drawPrimitives<Level: MultiLevelBufferLevel>(type: MTLPrimitiveType, indirectBuffer: MultiLevelBuffer<Level>,
                                                      indirectBufferLevel: Level, indirectBufferOffset: Int = 0)
    {
        indirectBuffer.bindSelfForDrawPrimitives(to:     self,
                                                 level:  indirectBufferLevel,
                                                 type:   type,
                                                 offset: indirectBufferOffset)
    }
    
    func drawIndexedPrimitives<Level: MultiLevelBufferLevel>(type: MTLPrimitiveType, indexType: MTLIndexType,
                                                             indexBuffer: MTLBuffer, indexBufferOffset: Int,
                                                             indirectBuffer: MultiLevelBuffer<Level>,
                                                             indirectBufferLevel: Level, indirectBufferOffset: Int = 0)
    {
        indirectBuffer.bindSelfForDrawIndexedPrimitives(to:                self,
                                                        level:             indirectBufferLevel,
                                                        type:              type,
                                                        indexType:         indexType,
                                                        indexBuffer:       indexBuffer,
                                                        indexBufferOffset: indexBufferOffset,
                                                        offset:            indirectBufferOffset)
    }
    
}

extension MTLIndirectRenderCommand {
    
    func setVertexBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                       offset: Int = 0, at index: Int) {
        buffer.bindSelfForVertex(to:       self,
                                 level:    level,
                                 offset:   offset,
                                 index:    index)
    }
    
    func setFragmentBuffer<Level: MultiLevelBufferLevel>(_ buffer: MultiLevelBuffer<Level>, level: Level,
                                                         offset: Int = 0, at index: Int) {
        buffer.bindSelfForVertex(to:       self,
                                 level:    level,
                                 offset:   offset,
                                 index:    index)
    }
    
}

extension MTLBlitCommandEncoder {
    
    func fill<Level: MultiLevelBufferLevel>(buffer: MultiLevelBuffer<Level>, level: Level, range: Range<Int>, value: UInt8) {
        buffer.fillSelf(with: self, level: level, range: range, value: value)
    }
    
}

extension MTLRasterizationRateMap {
    
    func copyParameterData<Level: MultiLevelBufferLevel>(buffer: MultiLevelBuffer<Level>, level: Level, offset: Int = 0) {
        buffer.copyVRRMap(vrrMap: self, level: level, offset: offset)
    }
    
}
