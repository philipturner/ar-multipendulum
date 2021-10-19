//
//  SIMDExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import simd

// Vectorized math functions

func fma(_ x: simd_float2, _ y: simd_float2, _ z: simd_float2) -> simd_float2 { __tg_fma(x, y, z) }
func fma(_ x: simd_float3, _ y: simd_float3, _ z: simd_float3) -> simd_float3 { __tg_fma(x, y, z) }
func fma(_ x: simd_float4, _ y: simd_float4, _ z: simd_float4) -> simd_float4 { __tg_fma(x, y, z) }
func fma(_ x: simd_double2, _ y: simd_double2, _ z: simd_double2) -> simd_double2 { __tg_fma(x, y, z) }

func fma(_ x: Float, _ y: simd_float2, _ z: simd_float2) -> simd_float2 { fma(.init(repeating: x), y, z) }
func fma(_ x: simd_float2, _ y: Float, _ z: simd_float2) -> simd_float2 { fma(y, x, z) }
func fma(_ x: simd_float2, _ y: simd_float2, _ z: Float) -> simd_float2 { fma(x, y, .init(repeating: z)) }
func fma(_ x: Float,       _ y: simd_float2, _ z: Float) -> simd_float2 { fma(x, y, .init(repeating: z)) }
func fma(_ x: simd_float2, _ y: Float,       _ z: Float) -> simd_float2 { fma(y, x, z) }

func fma(_ x: Float, _ y: simd_float3, _ z: simd_float3) -> simd_float3 { fma(.init(repeating: x), y, z) }
func fma(_ x: simd_float3, _ y: Float, _ z: simd_float3) -> simd_float3 { fma(y, x, z) }
func fma(_ x: simd_float3, _ y: simd_float3, _ z: Float) -> simd_float3 { fma(x, y, .init(repeating: z)) }
func fma(_ x: Float,       _ y: simd_float3, _ z: Float) -> simd_float3 { fma(x, y, .init(repeating: z)) }
func fma(_ x: simd_float3, _ y: Float,       _ z: Float) -> simd_float3 { fma(y, x, z) }

func fma(_ x: Float, _ y: simd_float4, _ z: simd_float4) -> simd_float4 { fma(.init(repeating: x), y, z) }
func fma(_ x: simd_float4, _ y: Float, _ z: simd_float4) -> simd_float4 { fma(y, x, z) }
func fma(_ x: simd_float4, _ y: simd_float4, _ z: Float) -> simd_float4 { fma(x, y, .init(repeating: z)) }
func fma(_ x: Float,       _ y: simd_float4, _ z: Float) -> simd_float4 { fma(x, y, .init(repeating: z)) }
func fma(_ x: simd_float4, _ y: Float,       _ z: Float) -> simd_float4 { fma(y, x, z) }

func fma(_ x: Double, _ y: simd_double2, _ z: simd_double2) -> simd_double2 { fma(.init(repeating: x), y, z) }
func fma(_ x: simd_double2, _ y: Double, _ z: simd_double2) -> simd_double2 { fma(y, x, z) }
func fma(_ x: simd_double2, _ y: simd_double2, _ z: Double) -> simd_double2 { fma(x, y, .init(repeating: z)) }
func fma(_ x: Double,       _ y: simd_double2, _ z: Double) -> simd_double2 { fma(x, y, .init(repeating: z)) }
func fma(_ x: simd_double2, _ y: Double,       _ z: Double) -> simd_double2 { fma(y, x, z) }

func sqrt(_ x: simd_float2) -> simd_float2 { __tg_sqrt(x) }
func sqrt(_ x: simd_float3) -> simd_float3 { __tg_sqrt(x) }
func sqrt(_ x: simd_float4) -> simd_float4 { __tg_sqrt(x) }
func sqrt(_ x: simd_double2) -> simd_double2 { __tg_sqrt(x) }

func sin(_ x: simd_float2) -> simd_float2 { __tg_sin(x) }
func sin(_ x: simd_float3) -> simd_float3 { __tg_sin(x) }
func sin(_ x: simd_float4) -> simd_float4 { __tg_sin(x) }
func sin(_ x: simd_double2) -> simd_double2 { __tg_sin(x) }

func cos(_ x: simd_float2) -> simd_float2 { __tg_cos(x) }
func cos(_ x: simd_float3) -> simd_float3 { __tg_cos(x) }
func cos(_ x: simd_float4) -> simd_float4 { __tg_cos(x) }
func cos(_ x: simd_double2) -> simd_double2 { __tg_cos(x) }

// Half Precision Vectors and Matrices

#if os(iOS)
typealias simd_half2 = SIMD2<Float16>

extension simd_half2 {
    init(_ x: Float, _ y: Float) {
        self.init(simd_float2(x, y))
    }
    
    init(_ vector: simd_half3) {
        self.init(vector.x, vector.y)
    }

    init(_ vector: simd_half4) {
        self.init(vector.x, vector.y)
    }
    
    init(_ vector: simd_float3) {
        self.init(simd_float2(vector.x, vector.y))
    }

    init(_ vector: simd_float4) {
        self.init(vector.lowHalf)
    }
}

struct simd_packed_half2: Equatable {
    var x: Float16
    var y: Float16
    
    var unpacked: simd_half2 {
        simd_half2(x, y)
    }
    
    
    
    init(_ x: Float16, _ y: Float16) {
        self.x = x
        self.y = y
    }
    
    init(_ x: Float, _ y: Float) {
        self.init(Float16(x), Float16(y))
    }
    
    
    
    init(_ vector: simd_half2) {
        self.init(vector.x, vector.y)
    }
    
    init(_ vector: simd_float2) {
        self.init(vector.x, vector.y)
    }
}

struct simd_half2x2: Equatable {
    var columns: (simd_half2, simd_half2)
    
    static func == (lhs: simd_half2x2, rhs: simd_half2x2) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1
    }
    
    init(_ col1: simd_half2, _ col2: simd_half2) {
        columns = (col1, col2)
    }
    
    init(_ col1: simd_float2, _ col2: simd_float2) {
        columns = (
            simd_half2(col1),
            simd_half2(col2)
        )
    }
    
    
    
    init(_ matrix: simd_half2x2) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
    
    init(_ matrix: simd_half3x3) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
    
    init(_ matrix: simd_half4x4) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
    
    
    
    init(_ matrix: simd_float2x2) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
    
    init(_ matrix: simd_float3x3) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
    
    init(_ matrix: simd_float4x4) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1)
        )
    }
}

let matrix_identity_half2x2 = simd_half2x2([1, 0],
                                simd_half2([0, 1]))

struct simd_half3x2: Equatable {
    var columns: (simd_half2, simd_half2, simd_half2)
    
    static func == (lhs: simd_half3x2, rhs: simd_half3x2) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2
    }
    
    init(_ col1: simd_half2, _ col2: simd_half2, _ col3: simd_half2) {
        columns = (col1, col2, col3)
    }
    
    init(_ col1: simd_float2, _ col2: simd_float2, _ col3: simd_float2) {
        columns = (
            simd_half2(col1),
            simd_half2(col2),
            simd_half2(col3)
        )
    }
    
    
    
    init(_ matrix: simd_half3x2) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1),
            simd_half2(matrix.columns.2)
        )
    }
    
    init(_ matrix: simd_float3x2) {
        columns = (
            simd_half2(matrix.columns.0),
            simd_half2(matrix.columns.1),
            simd_half2(matrix.columns.2)
        )
    }
}

typealias simd_half3 = SIMD3<Float16>

extension simd_half3 {
    init(_ vector: simd_half3) {
        self.init(vector.x, vector.y, vector.z)
    }
    
    init(_ vector: simd_half4) {
        self.init(vector.x, vector.y, vector.z)
    }
    
    
    
    init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(simd_float3(x, y, z))
    }
    
    init(_ xy: simd_float2, _ z: Float) {
        self.init(xy.x, xy.y, z)
    }
    
    init(_ vector: simd_float4) {
        self.init(vector.x, vector.y, vector.z)
    }
}

struct simd_packed_half3: Equatable {
    var x: Float16
    var y: Float16
    var z: Float16
    
    var unpacked: simd_half3 {
        simd_half3(x, y, z)
    }
    
    
    
    init(_ x: Float16, _ y: Float16, _ z: Float16) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(Float16(x), Float16(y), Float16(z))
    }
    
    
    
    init(_ vector: simd_half3) {
        self.init(vector.x, vector.y, vector.z)
    }
    
    init(_ vector: simd_float3) {
        self.init(vector.x, vector.y, vector.z)
    }
}

struct simd_half2x3: Equatable {
    var columns: (simd_half3, simd_half3)
    
    static func == (lhs: simd_half2x3, rhs: simd_half2x3) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1
    }
    
    init(_ col1: simd_half3, _ col2: simd_half3) {
        columns = (col1, col2)
    }
    
    init(_ col1: simd_float3, _ col2: simd_float3) {
        columns = (
            simd_half3(col1),
            simd_half3(col2)
        )
    }
    
    
    init(_ matrix: simd_half2x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1)
        )
    }
    
    init(_ matrix: simd_float2x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1)
        )
    }
}

struct simd_half3x3: Equatable {
    var columns: (simd_half3, simd_half3, simd_half3)
    
    static func == (lhs: simd_half3x3, rhs: simd_half3x3) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2
    }
    
    init(_ col1: simd_half3, _ col2: simd_half3, _ col3: simd_half3) {
        columns = (col1, col2, col3)
    }
    
    init(_ col1: simd_float3, _ col2: simd_float3, _ col3: simd_float3) {
        columns = (
            simd_half3(col1),
            simd_half3(col2),
            simd_half3(col3)
        )
    }
    
    
    
    init(_ matrix: simd_half3x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2)
        )
    }
    
    init(_ matrix: simd_half4x4) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2)
        )
    }
    
    
    
    init(_ matrix: simd_float3x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2)
        )
    }
    
    init(_ matrix: simd_float4x4) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2)
        )
    }
}

let matrix_identity_half3x3 = simd_half3x3([1, 0, 0],
                                simd_half3([0, 1, 0]),
                                           [0, 0, 1])
struct simd_half4x3: Equatable {
    var columns: (simd_half3, simd_half3, simd_half3, simd_half3)
    
    static func == (lhs: simd_half4x3, rhs: simd_half4x3) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2 &&
        lhs.columns.3 == rhs.columns.3
    }
    
    init(_ col1: simd_half3, _ col2: simd_half3, _ col3: simd_half3, _ col4: simd_half3) {
        columns = (col1, col2, col3, col4)
    }
    
    init(_ col1: simd_float3, _ col2: simd_float3, _ col3: simd_float3, _ col4: simd_float3) {
        columns = (
            simd_half3(col1),
            simd_half3(col2),
            simd_half3(col3),
            simd_half3(col4)
        )
    }
    
    
    
    init(_ matrix: simd_half4x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2),
            simd_half3(matrix.columns.3)
        )
    }
    
    init(_ matrix: simd_float4x3) {
        columns = (
            simd_half3(matrix.columns.0),
            simd_half3(matrix.columns.1),
            simd_half3(matrix.columns.2),
            simd_half3(matrix.columns.3)
        )
    }
}

typealias simd_half4 = SIMD4<Float16>

extension simd_half4 {
    init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.init(simd_float4(x, y, z, w))
    }
    
    init(_ xy: simd_float2, _ zw: simd_float2) {
        self.init(xy.x, xy.y, zw.x, zw.y)
    }
    
    init(_ xyz: simd_float3, _ w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
}

struct simd_packed_half4: Equatable {
    var x: Float16
    var y: Float16
    var z: Float16
    var w: Float16
    
    var unpacked: simd_half4 {
        simd_half4(x, y, z, w)
    }
    
    
    
    init(_ x: Float16, _ y: Float16, _ z: Float16, _ w: Float16) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    
    init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.init(Float16(x), Float16(y), Float16(z), Float16(w))
    }
    
    
    
    init(_ vector: simd_half4) {
        self.init(vector.x, vector.y, vector.z, vector.w)
    }
    
    init(_ vector: simd_float4) {
        self.init(vector.x, vector.y, vector.z, vector.w)
    }
}

struct simd_half4x4: Equatable {
    var columns: (simd_half4, simd_half4, simd_half4, simd_half4)
    
    static func == (lhs: simd_half4x4, rhs: simd_half4x4) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2 &&
        lhs.columns.3 == rhs.columns.3
    }
    
    init(_ col1: simd_half4, _ col2: simd_half4, _ col3: simd_half4, _ col4: simd_half4) {
        columns = (col1, col2, col3, col4)
    }
    
    init(_ col1: simd_float4, _ col2: simd_float4, _ col3: simd_float4, _ col4: simd_float4) {
        columns = (
            simd_half4(col1),
            simd_half4(col2),
            simd_half4(col3),
            simd_half4(col4)
        )
    }
    
    
    
    init(_ matrix: simd_half4x4) {
        columns = (
            simd_half4(matrix.columns.0),
            simd_half4(matrix.columns.1),
            simd_half4(matrix.columns.2),
            simd_half4(matrix.columns.3)
        )
    }
    
    init(_ matrix: simd_float4x4) {
        columns = (
            simd_half4(matrix.columns.0),
            simd_half4(matrix.columns.1),
            simd_half4(matrix.columns.2),
            simd_half4(matrix.columns.3)
        )
    }
}

let matrix_identity_half4x4 = simd_half4x4([1, 0, 0, 0],
                                simd_half4([0, 1, 0, 0]),
/* Other Vector Types */                   [0, 0, 1, 0],
                                           [0, 0, 0, 1])
#endif
struct simd_packed_float3: Equatable {
    var x: Float
    var y: Float
    var z: Float
    
    var unpacked: simd_float3 {
        simd_float3(x, y, z)
    }
    
    
    
    init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    init(_ vector: simd_float3) {
        self.init(vector.x, vector.y, vector.z)
    }
    
    
    
    #if os(iOS)
    init(_ x: Float16, _ y: Float16, _ z: Float16) {
        self.init(Float(x), Float(y), Float(z))
    }
    
    init(_ vector: simd_half3) {
        self.init(vector.x, vector.y, vector.z)
    }
    #endif
}

extension __float2 {
    var sinCosVector: simd_float2 { [__sinval, __cosval] }
    var cosSinVector: simd_float2 { [__cosval, __sinval] }
}

extension simd_float4x2 {
    var array: [simd_float2] {
        [columns.0, columns.1, columns.2, columns.3]
    }
}

extension simd_float4x3 {
    var array: [simd_float3] {
        [columns.0, columns.1, columns.2, columns.3]
    }
}

struct simd_packed_ushort3: Equatable {
    var x: UInt16
    var y: UInt16
    var z: UInt16
    
    init(_ vector: simd_ushort3) {
        x = vector.x
        y = vector.y
        z = vector.z
    }
    
    var unpackedVector: simd_ushort3 {
        simd_ushort3(x, y, z)
    }
}

struct simd_packed_uint3: Equatable {
    var x: UInt32
    var y: UInt32
    var z: UInt32
    
    init(_ vector: simd_uint3) {
        x = vector.x
        y = vector.y
        z = vector.z
    }
    
    var unpackedVector: simd_uint3 {
        simd_uint3(x, y, z)
    }
}

struct simd_bool2: Equatable {
    private var data: simd_uchar2
    
    init(_ x: Bool, _ y: Bool) {
        data = simd_uchar2(x ? 1 : 0, y ? 1 : 0)
    }
    
    subscript(_ index: Int) -> Bool {
        get { data[index] != 0 }
        set {
            data[index] = newValue ? 1 : 0
        }
    }
}
