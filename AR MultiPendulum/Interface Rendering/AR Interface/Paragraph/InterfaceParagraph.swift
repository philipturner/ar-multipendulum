//
//  InterfaceParagraph.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/12/21.
//

import Foundation

protocol InterfaceParagraph {
    static var parameters: Parameters { get }
}

extension InterfaceParagraph {
    typealias Parameters = (stringSegments: [InterfaceRenderer.StringSegment], width: Float, pixelSize: Float)
    typealias StringSegment = InterfaceRenderer.StringSegment
}

extension InterfaceRenderer {
    
    typealias ParagraphParameters = InterfaceParagraph.Parameters
    
    private static let cachingQueue = DispatchQueue(label: "Interface Renderer Cached Paragraph Caching Queue", qos: .userInitiated)
    private static var pendingParagraphParameters: [ParagraphParameters] = []
    
    static var _fontHandles: [FontHandle] = []
    static var fontHandles: [FontHandle] {
        get { _fontHandles }
        set {
            var paragraphsToCache: [ParagraphParameters]!
            
            cachingQueue.sync {
                _fontHandles = newValue
                paragraphsToCache = pendingParagraphParameters
                pendingParagraphParameters = []
            }
            
            for parameters in paragraphsToCache {
                _ = createParagraph(stringSegments: parameters.stringSegments, width: parameters.width, pixelSize: parameters.pixelSize)
            }
        }
    }
    
    private struct Key: Hashable {
        var strings: [String]
        var fontIDs: [Int]
        
        var width: Float
        var pixelSize: Float
        
        init(parameters: ParagraphParameters) {
            strings = parameters.stringSegments.map{ $0.string }
            fontIDs = parameters.stringSegments.map{ $0.fontID }
            
            width = parameters.width
            pixelSize = parameters.pixelSize
        }
    }
    
    private static let registryQueue = DispatchQueue(label: "Interface Renderer Cached Paragraph Registry Queue", qos: .userInitiated)
    private static var cachedParagraphs: [Key : ParagraphReturn] = [:]
    
    static func searchForParagraph(_ parameters: ParagraphParameters) -> ParagraphReturn? {
        registryQueue.sync{ cachedParagraphs[Key(parameters: parameters)] }
    }
    
    static func registerParagraphReturn(_ parameters: ParagraphParameters, _ paragraphReturn: ParagraphReturn) {
        registryQueue.sync{ cachedParagraphs[Key(parameters: parameters)] = paragraphReturn }
    }
    
    fileprivate static func cacheParagraph(_ parameters: ParagraphParameters) {
        var fontHandlesExist = false
        
        cachingQueue.sync {
            if _fontHandles.count == 0 {
                pendingParagraphParameters.append(parameters)
            } else {
                fontHandlesExist = true
            }
        }
        
        if fontHandlesExist {
            _ = createParagraph(stringSegments: parameters.stringSegments, width: parameters.width, pixelSize: parameters.pixelSize)
        }
    }
    
}



protocol InterfaceParagraphList: CaseIterable {
    var parameters: InterfaceParagraph.Parameters { get }
}

protocol InterfaceParagraphContainer {
    associatedtype CachedParagraph: InterfaceParagraphList
}

extension InterfaceParagraphList {
    typealias Parameters = InterfaceParagraph.Parameters
}

extension InterfaceParagraphContainer {
    static func cacheParagraphs() {
        for paragraph in CachedParagraph.allCases {
            InterfaceRenderer.cacheParagraph(paragraph.parameters)
        }
    }
    
    static func createParagraph(_ paragraph: CachedParagraph) -> InterfaceRenderer.ParagraphReturn {
        let parameters = paragraph.parameters
        return InterfaceRenderer.createParagraph(stringSegments: parameters.stringSegments, width: parameters.width,
                                                 pixelSize: parameters.pixelSize)
    }
}
