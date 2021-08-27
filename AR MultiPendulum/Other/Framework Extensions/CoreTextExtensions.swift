//
//  CoreTextExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/22/21.
//

import Foundation
import CoreText

// High-level wrappers around the CoreText framework

extension Optional where Wrapped == CTFont {
    init<T: BinaryFloatingPoint>(_ name: String, _ size: T, _ matrix: UnsafePointer<CGAffineTransform>?, _ options: CTFontOptions? = nil) {
        if let options = options {
            self = CTFontCreateWithNameAndOptions(name as CFString, CGFloat(size), matrix, options)
        } else {
            self = CTFontCreateWithName(name as CFString, CGFloat(size), matrix)
        }
    }
    
    init<T: BinaryFloatingPoint>(_ descriptor: CTFontDescriptor, _ size: T, _ matrix: UnsafePointer<CGAffineTransform>?,
                                 _ options: CTFontOptions? = nil) {
        if let options = options {
            self = CTFontCreateWithFontDescriptorAndOptions(descriptor, CGFloat(size), matrix, options)
        } else {
            self = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), matrix)
        }
    }
    
    init<T: BinaryFloatingPoint>(_ uiType: CTFontUIFontType, _ size: T, _ language: String?) {
        self = CTFontCreateUIFontForLanguage(uiType, CGFloat(size), language as CFString?)
    }
    
    init(_ currentFont: CTFont, _ string: String, _ range: Range<Int>, _ language: String? = nil) {
        if let language = language {
            self = CTFontCreateForStringWithLanguage(currentFont, string as CFString, range.asCFRange, language as CFString)
        } else {
            self = CTFontCreateForString(currentFont, string as CFString, range.asCFRange)
        }
    }
    
    init<T: BinaryFloatingPoint>(_ graphicsFont: CGFont, _ size: T, _ matrix: UnsafePointer<CGAffineTransform>?,
                                 _ attributes: CTFontDescriptor?) {
        self = CTFontCreateWithGraphicsFont(graphicsFont, CGFloat(size), matrix, attributes)
    }
}

extension Optional where Wrapped == CTFontDescriptor {
    init<T: BinaryFloatingPoint>(_ name: String, _ size: T) {
        self = CTFontDescriptorCreateWithNameAndSize(name as CFString, CGFloat(size))
    }
    
    init(_ attributes: [CFString : Any]) {
        self = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    }
}

extension Optional where Wrapped == CTLine {
    init(_ attrString: NSAttributedString) {
        self = CTLineCreateWithAttributedString(attrString as CFAttributedString)
    }
}

extension Optional where Wrapped == CTParagraphStyle {
    init(_ settings: UnsafePointer<CTParagraphStyleSetting>?, _ settingCount: Int) {
        self = CTParagraphStyleCreate(settings, settingCount)
    }
}

extension Optional where Wrapped == CTFontCollection {
    init(_ options: [CFString : Any]) {
        self = CTFontCollectionCreateFromAvailableFonts(options as CFDictionary)
    }
    
    init(_ queryDescriptors: [CTFontDescriptor]?, _ options: [CFString : Any]) {
        self = CTFontCollectionCreateWithFontDescriptors(queryDescriptors as CFArray?, options as CFDictionary)
    }
}

extension Optional where Wrapped == CTRubyAnnotation {
    init<T: BinaryFloatingPoint>(_ alignment: CTRubyAlignment, _ overhang: CTRubyOverhang, _ sizeFactor: T,
                                 _ text: UnsafeMutablePointer<Unmanaged<CFString>?>) {
        self = CTRubyAnnotationCreate(alignment, overhang, CGFloat(sizeFactor), text)
    }
    
    init(_ alignment: CTRubyAlignment, _ overhang: CTRubyOverhang, _ position: CTRubyPosition,
         _ string: String, _ attributes: [CFString : Any]) {
        self = CTRubyAnnotationCreateWithAttributes(alignment, overhang, position, string as CFString, attributes as CFDictionary)
    }
}

extension Optional where Wrapped == CTTypesetter {
    init(_ string: NSAttributedString) {
        self = CTTypesetterCreateWithAttributedString(string as CFAttributedString)
    }
    
    init(_ string: NSAttributedString, _ options: [CFString : Any]) {
        self = CTTypesetterCreateWithAttributedStringAndOptions(string as CFAttributedString, options as CFDictionary)
    }
}

extension Optional where Wrapped == CTGlyphInfo {
    init(_ glyphName: String, _ font: CTFont, _ baseString: String) {
        self = CTGlyphInfoCreateWithGlyphName(glyphName as CFString, font, baseString as CFString)
    }
    
    init(_ glyph: CGGlyph, _ font: CTFont, _ baseString: String) {
        self = CTGlyphInfoCreateWithGlyph(glyph, font, baseString as CFString)
    }
    
    init(_ cid: CGFontIndex, _ collection: CTCharacterCollection, _ baseString: CFString) {
        self = CTGlyphInfoCreateWithCharacterIdentifier(cid, collection, baseString as CFString)
    }
}

extension Optional where Wrapped == CTFramesetter {
    init(_ typesetter: CTTypesetter) {
        self = CTFramesetterCreateWithTypesetter(typesetter)
    }
    
    init(_ attrString: NSAttributedString) {
        self = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
    }
}

extension Optional where Wrapped == CTRunDelegate {
    init(_ callbacks: UnsafePointer<CTRunDelegateCallbacks>, _ refCon: UnsafeMutableRawPointer?) {
        self = CTRunDelegateCreate(callbacks, refCon)
    }
}

extension Optional where Wrapped == CTTextTab {
    init<T: BinaryFloatingPoint>(_ alignment: CTTextAlignment, _ location: T, _ options: [CFString : Any]?) {
        self = CTTextTabCreate(alignment, Double(location), options as CFDictionary?)
    }
}



extension CTFont {
    func createCopy<T: BinaryFloatingPoint>(_ size: T, _ matrix: UnsafePointer<CGAffineTransform>?,
                                            _ attributes: CTFontDescriptor?) -> CTFont {
        CTFontCreateCopyWithAttributes(self, CGFloat(size), matrix, attributes)
    }
    
    func createCopy<T: BinaryFloatingPoint>(_ size: T, _ matrix: UnsafePointer<CGAffineTransform>?,
                                            _ symTraitValue: CTFontSymbolicTraits, _ symTraitMask: CTFontSymbolicTraits) -> CTFont? {
        CTFontCreateCopyWithSymbolicTraits(self, CGFloat(size), matrix, symTraitValue, symTraitMask)
    }
    
    func createCopy<T: BinaryFloatingPoint>(_ size: T, _ matrix: UnsafePointer<CGAffineTransform>?, _ family: String) -> CTFont? {
        CTFontCreateCopyWithFamily(self, CGFloat(size), matrix, family as CFString)
    }
    
    var fontDescriptor: CTFontDescriptor { CTFontCopyFontDescriptor(self) }
    
    func copyAttribute(_ attribute: CFString) -> CFTypeRef? {
        CTFontCopyAttribute(self, attribute as CFString)
    }
    
    var size: CGFloat { CTFontGetSize(self) }
    var matrix: CGAffineTransform { CTFontGetMatrix(self) }
    var symbolicTraits: CTFontSymbolicTraits { CTFontGetSymbolicTraits(self) }
    var traits: [CFString : Any] { CTFontCopyTraits(self) as! Dictionary }
    
    var postScriptName: String { CTFontCopyPostScriptName(self) as String }
    var familyName: String { CTFontCopyFamilyName(self) as String }
    var fullName: String { CTFontCopyFullName(self) as String }
    var displayName: String { CTFontCopyDisplayName(self) as String }
    
    func copyName(_ nameKey: String) -> String? {
        CTFontCopyName(self, nameKey as CFString) as String?
    }
    
    func copyLocalizedName(_ nameKey: String, _ actualLanguage: UnsafeMutablePointer<Unmanaged<CFString>?>?) -> String? {
        CTFontCopyLocalizedName(self, nameKey as CFString, actualLanguage) as String?
    }
    
    var characterSet: CFCharacterSet { CTFontCopyCharacterSet(self) }
    var stringEncoding: CFStringEncoding { CTFontGetStringEncoding(self) }
    var supportedLanguages: [String] { CTFontCopySupportedLanguages(self) as! Array }
    
    func getGlyphs(_ characters: UnsafePointer<UniChar>, _ glyphs: UnsafeMutablePointer<CGGlyph>, _ count: Int) -> Bool {
        CTFontGetGlyphsForCharacters(self, characters, glyphs, count)
    }
    
    var ascent: CGFloat { CTFontGetAscent(self) }
    var descent: CGFloat { CTFontGetDescent(self) }
    var leading: CGFloat { CTFontGetLeading(self) }
    var unitsPerEm: UInt32 { CTFontGetUnitsPerEm(self) }
    var glyphCount: Int { CTFontGetGlyphCount(self) }
    
    var boundingBox: CGRect { CTFontGetBoundingBox(self) }
    var underlinePosition: CGFloat { CTFontGetUnderlinePosition(self) }
    var underlineThickness: CGFloat { CTFontGetUnderlineThickness(self) }
    var slantAngle: CGFloat { CTFontGetSlantAngle(self) }
    var capHeight: CGFloat { CTFontGetCapHeight(self) }
    var xHeight: CGFloat { CTFontGetXHeight(self) }
    
    func getGlyph(_ glyphName: String) -> CGGlyph { CTFontGetGlyphWithName(self, glyphName as CFString) }
    func getName(_ glyph: CGGlyph) -> String? { CTFontCopyNameForGlyph(self, glyph) as String? }
    
    func getBoundingRects(_ orientation: CTFontOrientation, _ glyphs: UnsafePointer<CGGlyph>,
                          _ boundingRects: UnsafeMutablePointer<CGRect>?, _ count: Int) -> CGRect {
        CTFontGetBoundingRectsForGlyphs(self, orientation, glyphs, boundingRects, count)
    }
    
    func getOpticalBounds(_ glyphs: UnsafePointer<CGGlyph>, _ boundingRects: UnsafeMutablePointer<CGRect>?,
                          _ count: Int, _ options: CFOptionFlags) -> CGRect {
        CTFontGetOpticalBoundsForGlyphs(self, glyphs, boundingRects, count, options)
    }
    
    func getAdvances(_ orientation: CTFontOrientation, _ glyphs: UnsafePointer<CGGlyph>,
                     _ advances: UnsafeMutablePointer<CGSize>?, _ count: Int) -> Double {
        CTFontGetAdvancesForGlyphs(self, orientation, glyphs, advances, count)
    }
    
    func getVerticalTranslations(_ glyphs: UnsafePointer<CGGlyph>, _ translations: UnsafeMutablePointer<CGSize>, _ count: Int) {
        CTFontGetVerticalTranslationsForGlyphs(self, glyphs, translations, count)
    }
    
    func createPath(_ glyph: CGGlyph, _ matrix: UnsafePointer<CGAffineTransform>?) -> CGPath? {
        CTFontCreatePathForGlyph(self, glyph, matrix)
    }
    
    var variationAxes: [[CFString : Any]] { CTFontCopyVariationAxes(self) as! Array }
    var variation: [CFString : Any] { CTFontCopyVariation(self) as! Dictionary }
    var features: [[CFString : Any]] { CTFontCopyFeatures(self) as! Array }
    var featureSettings: [[CFString : Any ]] { CTFontCopyFeatureSettings(self) as! Array }
    
    func copyGraphicsFont(_ attributes: UnsafeMutablePointer<Unmanaged<CTFontDescriptor>?>?) -> CGFont {
        CTFontCopyGraphicsFont(self, attributes)
    }
    
    func copyAvailableTables(_ options: CTFontTableOptions) -> [CTFontTableTag]? {
        CTFontCopyAvailableTables(self, options) as! Array?
    }
    
    func copyTable(_ table: CTFontTableTag, _ options: CTFontTableOptions) -> Data? {
        CTFontCopyTable(self, table, options) as Data?
    }
    
    func drawGlyphs(_ glyphs: UnsafePointer<CGGlyph>, _ positions: UnsafePointer<CGPoint>, _ count: Int, _ context: CGContext) {
        CTFontDrawGlyphs(self, glyphs, positions, count, context)
    }
    
    func getLigatureCaretPositions(_ glyph: CGGlyph, _ positions: UnsafeMutablePointer<CGFloat>?, _ maxPositions: Int) -> Int {
        CTFontGetLigatureCaretPositions(self, glyph, positions, maxPositions)
    }
    
    func copyDefaultCascadeList(_ languagePrefList: [String]?) -> [CTFontDescriptor]? {
        CTFontCopyDefaultCascadeListForLanguages(self, languagePrefList as CFArray?) as! Array?
    }
}

extension CTFontDescriptor {
    static var typeID: CFTypeID { CTFontDescriptorGetTypeID() }
    
    func createCopy(_ attributes: [CFString : Any]) -> CTFontDescriptor {
        CTFontDescriptorCreateCopyWithAttributes(self, attributes as CFDictionary)
    }
    
    func createCopy(_ family: String) -> CTFontDescriptor? {
        CTFontDescriptorCreateCopyWithFamily(self, family as CFString)
    }
    
    func createCopy(_ symTraitValue: CTFontSymbolicTraits, _ symTraitMask: CTFontSymbolicTraits) -> CTFontDescriptor? {
        CTFontDescriptorCreateCopyWithSymbolicTraits(self, symTraitValue, symTraitMask)
    }
    
    func createCopy<T: BinaryFloatingPoint>(_ variationIdentifier: CFNumber, _ variationValue: T) -> CTFontDescriptor {
        CTFontDescriptorCreateCopyWithVariation(self, variationIdentifier, CGFloat(variationValue))
    }
    
    func createCopy(_ featureTypeIdentifier: CFNumber, _ featureSelectorIdentifier: CFNumber) -> CTFontDescriptor {
        CTFontDescriptorCreateCopyWithFeature(self, featureTypeIdentifier, featureSelectorIdentifier)
    }
    
    func createMatchingFontDescriptors(_ mandatoryAttributes: Set<CFString>?) -> [CTFontDescriptor]? {
        CTFontDescriptorCreateMatchingFontDescriptors(self, mandatoryAttributes as CFSet?) as! Array?
    }
    
    func createMatchingFontDescriptor(_ mandatoryAttributes: Set<CFString>?) -> CTFontDescriptor? {
        CTFontDescriptorCreateMatchingFontDescriptor(self, mandatoryAttributes as CFSet?)
    }
    
    static func matchFontDescriptors(_ descriptors: [CTFontDescriptor], _ mandatoryAttributes: Set<CFString>?,
                                     _ progressBlock: @escaping CTFontDescriptorProgressHandler) -> Bool {
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, mandatoryAttributes as CFSet?, progressBlock)
    }
    
    var attributes: [CFString : Any] { CTFontDescriptorCopyAttributes(self) as! Dictionary }
    
    func copyAttribute(_ attribute: CFString) -> CFTypeRef? {
        CTFontDescriptorCopyAttribute(self, attribute)
    }
    
    func copyLocalizedAttribute(_ attribute: CFString, _ language: UnsafeMutablePointer<Unmanaged<CFString>?>?) -> CFTypeRef? {
        CTFontDescriptorCopyLocalizedAttribute(self, attribute, language)
    }
}

enum CTFontManager {
    static var availablePostScriptNames: [String] { CTFontManagerCopyAvailablePostScriptNames() as! Array }
    static var availableFontFamilyNames: [String] { CTFontManagerCopyAvailableFontFamilyNames() as! Array }
    
    static func createFontDescriptors(_ fileURL: URL) -> [CTFontDescriptor]? {
        CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as! Array?
    }
    
    static func createFontDescriptor(_ data: Data) -> CTFontDescriptor? {
        CTFontManagerCreateFontDescriptorFromData(data as CFData)
    }
    
    static func createFontDescriptors(_ data: Data) -> [CTFontDescriptor] {
        CTFontManagerCreateFontDescriptorsFromData(data as CFData) as! Array
    }
    
    static func registerFonts(_ fontURL: URL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, scope, error)
    }
    
    static func unregisterFonts(_ fontURL: URL, _ scope: CTFontManagerScope, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
        CTFontManagerUnregisterFontsForURL(fontURL as CFURL, scope, error)
    }
    
    static func registerGraphicsFont(_ font: CGFont, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
        CTFontManagerRegisterGraphicsFont(font, error)
    }
    
    static func unregisterGraphicsFont(_ font: CGFont, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool {
        CTFontManagerUnregisterGraphicsFont(font, error)
    }
    
    static func registerFontURLs(_ fontURLs: [URL], _ scope: CTFontManagerScope, _ enabled: Bool,
                                 _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
        CTFontManagerRegisterFontURLs(fontURLs as CFArray, scope, enabled, registrationHandler)
    }
    
    static func unregisterFontURLs(_ fontURLs: [URL], _ scope: CTFontManagerScope, _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
        CTFontManagerUnregisterFontURLs(fontURLs as CFArray, scope, registrationHandler)
    }
    
    static func registerFontDescriptors(_ fontDescriptors: [CTFontDescriptor], _ scope: CTFontManagerScope, _ enabled: Bool,
                                        _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
        CTFontManagerRegisterFontDescriptors(fontDescriptors as CFArray, scope, enabled, registrationHandler)
    }
    
    static func unregisterFontDescriptors(_ fontDescriptors: [CTFontDescriptor], _ scope: CTFontManagerScope,
                                          _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
        CTFontManagerUnregisterFontDescriptors(fontDescriptors as CFArray, scope, registrationHandler)
    }
    
    #if os(iOS)
    static func registerFonts(_ fontAssetNames: [String], _ bundle: CFBundle?, _ scope: CTFontManagerScope, _ enabled: Bool,
                              _ registrationHandler: ((CFArray, Bool) -> Bool)?) {
        CTFontManagerRegisterFontsWithAssetNames(fontAssetNames as CFArray, bundle, scope, enabled, registrationHandler)
    }
    
    static func registeredFontDescriptors(_ scope: CTFontManagerScope, _ enabled: Bool) -> [CTFontDescriptor] {
        CTFontManagerCopyRegisteredFontDescriptors(scope, enabled) as! Array
    }
    
    static func requestFonts(_ fontDescriptors: [CTFontDescriptor], _ completionHandler: @escaping (CFArray) -> Void) {
        CTFontManagerRequestFonts(fontDescriptors as CFArray, completionHandler)
    }
    #endif
}

extension CTFrame {
    static var typeID: CFTypeID { CTFrameGetTypeID() }
    
    var stringRange: Range<Int> { .init(CTFrameGetStringRange(self)) }
    var visibleStringRange: Range<Int> { .init(CTFrameGetVisibleStringRange(self)) }
    var path: CGPath { CTFrameGetPath(self) }
    var attributes: [CFString : Any] { CTFrameGetFrameAttributes(self) as! Dictionary }
    var lines: [CTLine] { CTFrameGetLines(self) as! Array }
    
    func getLineOrigins(_ range: Range<Int>, origins: UnsafeMutablePointer<CGPoint>) {
        CTFrameGetLineOrigins(self, range.asCFRange, origins)
    }
    
    func draw(_ context: CGContext) {
        CTFrameDraw(self, context)
    }
}

extension CTLine {
    static var typeID: CFTypeID { CTLineGetTypeID() }
    
    func createTruncatedLine<T: BinaryFloatingPoint>(_ width: T, _ truncationType: CTLineTruncationType,
                                                     _ truncationToken: CTLine?) -> CTLine? {
        CTLineCreateTruncatedLine(self, Double(width), truncationType, truncationToken)
    }
    
    func createJustifiedLine<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ justificationFactor: S, _ justificationWidth: T) -> CTLine? {
        CTLineCreateJustifiedLine(self, CGFloat(justificationFactor), Double(justificationWidth))
    }
    
    var glyphCount: Int { CTLineGetGlyphCount(self) }
    var glyphRuns: [CTRun] { CTLineGetGlyphRuns(self) as! Array }
    var stringRange: Range<Int> { .init(CTLineGetStringRange(self)) }
    
    func getPenOffset<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ flushFactor: S, _ flushWidth: T) -> Double {
        CTLineGetPenOffsetForFlush(self, CGFloat(flushFactor), Double(flushWidth))
    }
    
    func draw(_ context: CGContext) {
        CTLineDraw(self, context)
    }
    
    func getTypographicBounds(_ ascent: UnsafeMutablePointer<CGFloat>?, _ descent: UnsafeMutablePointer<CGFloat>?,
                              _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
        CTLineGetTypographicBounds(self, ascent, descent, leading)
    }
    
    func getBounds(_ options: CTLineBoundsOptions) -> CGRect {
        CTLineGetBoundsWithOptions(self, options)
    }
    
    var trailingWhitespaceWidth: Double { CTLineGetTrailingWhitespaceWidth(self) }
    
    func getImageBounds(_ context: CGContext?) -> CGRect {
        CTLineGetImageBounds(self, context)
    }
    
    func getStringIndex(_ position: CGPoint) -> Int {
        CTLineGetStringIndexForPosition(self, position)
    }
    
    func getOffset(_ charIndex: Int, _ secondaryOffset: UnsafeMutablePointer<CGFloat>?) -> CGFloat {
        CTLineGetOffsetForStringIndex(self, charIndex, secondaryOffset)
    }
    
    func enumerateCaretOffsets(_ closure: @escaping (Double, Int, Bool, UnsafeMutablePointer<Bool>) -> Void) {
        CTLineEnumerateCaretOffsets(self, closure)
    }
}

extension CTRun {
    static var typeID: CFTypeID { CTRunGetTypeID() }
    
    var glyphCount: Int { CTRunGetGlyphCount(self) }
    var attributes: [CFString : Any] { CTRunGetAttributes(self) as! Dictionary }
    var status: CTRunStatus { CTRunGetStatus(self) }
    
    var glyphsPtr: UnsafePointer<CGGlyph>? { CTRunGetGlyphsPtr(self) }
    var positionsPtr: UnsafePointer<CGPoint>? { CTRunGetPositionsPtr(self) }
    var advancesPointer: UnsafePointer<CGSize>? { CTRunGetAdvancesPtr(self) }
    var stringIndicesPtr: UnsafePointer<Int>? { CTRunGetStringIndicesPtr(self) }
    
    func getGlyphs(_ range: Range<Int>, _ buffer: UnsafeMutablePointer<CGGlyph>) {
        CTRunGetGlyphs(self, range.asCFRange, buffer)
    }
    
    func getPositions(_ range: Range<Int>, _ buffer: UnsafeMutablePointer<CGPoint>) {
        CTRunGetPositions(self, range.asCFRange, buffer)
    }
    
    func getAdvances(_ range: Range<Int>, _ buffer: UnsafeMutablePointer<CGSize>) {
        CTRunGetAdvances(self, range.asCFRange, buffer)
    }
    
    func getStringIndices(_ range: Range<Int>, _ buffer: UnsafeMutablePointer<Int>) {
        CTRunGetStringIndices(self, range.asCFRange, buffer)
    }
    
    var stringRange: Range<Int> { .init(CTRunGetStringRange(self)) }
    
    func getTypographicBounds(_ range: Range<Int>, _ ascent: UnsafeMutablePointer<CGFloat>?,
                              _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
        CTRunGetTypographicBounds(self, range.asCFRange, ascent, descent, leading)
    }
    
    func getImageBounds(_ context: CGContext?, _ range: CFRange) -> CGRect {
        CTRunGetImageBounds(self, context, range)
    }
    
    var textMatrix: CGAffineTransform { CTRunGetTextMatrix(self) }
    
    func getBaseAdvancesAndOrigins(_ range: Range<Int>, _ advancesBuffer: UnsafeMutablePointer<CGSize>?,
                                   _ originsBuffer: UnsafeMutablePointer<CGPoint>?) {
        CTRunGetBaseAdvancesAndOrigins(self, range.asCFRange, advancesBuffer, originsBuffer)
    }
    
    func draw(_ context: CGContext, _ range: Range<Int>) {
        CTRunDraw(self, context, range.asCFRange)
    }
}

extension CTParagraphStyle {
    static var typeID: CFTypeID { CTParagraphStyleGetTypeID() }
    
    var copy: CTParagraphStyle { CTParagraphStyleCreateCopy(self) }
    
    func getValue(_ spec: CTParagraphStyleSpecifier, _ valueBufferSize: Int, _ valueBuffer: UnsafeMutableRawPointer) -> Bool {
        CTParagraphStyleGetValueForSpecifier(self, spec, valueBufferSize, valueBuffer)
    }
}

extension CTFontCollection {
    static var typeID: CFTypeID { CTFontCollectionGetTypeID() }
    
    func createCopy(_ queryDescriptors: [CTFontDescriptor]?, _ options: [CFString : Any]) -> CTFontCollection {
        CTFontCollectionCreateCopyWithFontDescriptors(self, queryDescriptors as CFArray?, options as CFDictionary)
    }
    
    var matchingFontDescriptors: [CTFontDescriptor]? { CTFontCollectionCreateMatchingFontDescriptors(self) as! Array? }
    
    func createMatchingFontDescriptors(_ sortCallback: CTFontCollectionSortDescriptorsCallback?,
                                       _ refCon: UnsafeMutableRawPointer?) -> [CTFontCollection]? {
        CTFontCollectionCreateMatchingFontDescriptorsSortedWithCallback(self, sortCallback, refCon) as! Array?
    }
    
    func createMatchingFontDescriptors(_ options: [CFString : Any]) -> [CTFontDescriptor]? {
        CTFontCollectionCreateMatchingFontDescriptorsWithOptions(self, options as CFDictionary) as! Array?
    }
}

extension CTRubyAnnotation {
    static var typeID: CFTypeID { CTRubyAnnotationGetTypeID() }
    
    var copy: CTRubyAnnotation { CTRubyAnnotationCreateCopy(self) }
    var alignment: CTRubyAlignment { CTRubyAnnotationGetAlignment(self) }
    var overhang: CTRubyOverhang { CTRubyAnnotationGetOverhang(self) }
    var sizeFactor: CGFloat { CTRubyAnnotationGetSizeFactor(self) }
    
    func getText(_ position: CTRubyPosition) -> String? {
        CTRubyAnnotationGetTextForPosition(self, position) as String?
    }
}

extension CTTypesetter {
    static var typeID: CFTypeID { CTTypesetterGetTypeID() }
    
    func createLine<T: BinaryFloatingPoint>(_ stringRange: Range<Int>, _ offset: T? = nil) -> CTLine {
        if let offset = offset {
            return CTTypesetterCreateLineWithOffset(self, stringRange.asCFRange, Double(offset))
        } else {
            return CTTypesetterCreateLine(self, stringRange.asCFRange)
        }
    }
    
    func suggestLineBreak<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ startIndex: Int, _ width: S, _ offset: T? = nil) -> Int {
        if let offset = offset {
            return CTTypesetterSuggestLineBreakWithOffset(self, startIndex, Double(width), Double(offset))
        } else {
            return CTTypesetterSuggestLineBreak(self, startIndex, Double(width))
        }
    }
    
    func suggestClusterBreak<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ startIndex: Int, _ width: S, _ offset: T? = nil) -> Int {
        if let offset = offset {
            return CTTypesetterSuggestClusterBreakWithOffset(self, startIndex, Double(width), Double(offset))
        } else {
            return CTTypesetterSuggestClusterBreak(self, startIndex, Double(width))
        }
    }
}

extension CTGlyphInfo {
    static var typeID: CFTypeID {CTGlyphInfoGetTypeID() }
    
    var name: String? { CTGlyphInfoGetGlyphName(self) as String? }
    var glyph: CGGlyph { CTGlyphInfoGetGlyph(self) }
    var characterIdentifier: CGFontIndex { CTGlyphInfoGetCharacterIdentifier(self) }
    var characterCollection: CTCharacterCollection { CTGlyphInfoGetCharacterCollection(self) }
}

extension CTFramesetter {
    static var typeID: CFTypeID { CTFramesetterGetTypeID() }
    
    func createFrame(_ stringRange: Range<Int>, _ path: CGPath, _ frameAttributes: [CFString : Any]) -> CTFrame {
        CTFramesetterCreateFrame(self, stringRange.asCFRange, path, frameAttributes as CFDictionary)
    }
    
    var typesetter: CTTypesetter { CTFramesetterGetTypesetter(self) }
    
    func suggestFrameSize(_ stringRange: Range<Int>, _ frameAttributes: [CFString : Any]?, _ constraints: CGSize,
                          _ fitRange: UnsafeMutablePointer<CFRange>?) -> CGSize {
        CTFramesetterSuggestFrameSizeWithConstraints(self, stringRange.asCFRange, frameAttributes as CFDictionary?, constraints, fitRange)
    }
}

extension CTRunDelegate {
    static var typeID: CFTypeID { CTRunDelegateGetTypeID() }
    
    var refCon: UnsafeMutableRawPointer { CTRunDelegateGetRefCon(self) }
}

extension CTTextTab {
    static var typeID: CFTypeID { CTTextTabGetTypeID() }
    
    var alignment: CTTextAlignment { CTTextTabGetAlignment(self) }
    var location: Double { CTTextTabGetLocation(self) }
    var options: [CFString : Any] { CTTextTabGetOptions(self) as! Dictionary }
}
