// RUN: tf_tfl_translate --enable-hlo-to-tf-conversion --input-mlir %s -o - | flatbuffer_translate --tflite-flatbuffer-to-mlir - -o - | FileCheck %s --check-prefix=CHECK-ROUNDTRIP


module {
  // CHECK-LABEL: func.func public @main
  func.func public @main(%arg0: tensor<3x2x4x7x9xi32>, %arg1: tensor<4x3x5x2xi32>) -> tensor<4x3x5x8xi32> {
    // CHECK-ROUNDTRIP:       %0 = "tfl.pseudo_const"() <{value = dense<{{\[\[\[\[}}0]], {{\[\[}}1]], {{\[\[}}2]]]]> : tensor<1x3x1x1xi32>}> : () -> tensor<1x3x1x1xi32>
    // CHECK-ROUNDTRIP:       %1 = "tfl.pseudo_const"() <{value = dense<[4, 3, 5, 1]> : tensor<4xi64>}> : () -> tensor<4xi64>
    // CHECK-ROUNDTRIP:       %2 = "tfl.broadcast_to"(%0, %1) : (tensor<1x3x1x1xi32>, tensor<4xi64>) -> tensor<4x3x5x1xi32>
    // CHECK-ROUNDTRIP:       %3 = "tfl.pseudo_const"() <{value = dense<{{\[\[\[\[}}0]]], {{\[\[\[}}1]]], {{\[\[\[}}2]]], {{\[\[\[}}3]]]]> : tensor<4x1x1x1xi32>}> : () -> tensor<4x1x1x1xi32>
    // CHECK-ROUNDTRIP:       %4 = "tfl.broadcast_to"(%3, %1) : (tensor<4x1x1x1xi32>, tensor<4xi64>) -> tensor<4x3x5x1xi32>
    // CHECK-ROUNDTRIP:       %[[concat:.*]] = "tfl.concatenation"(%2, %4, %arg1) <{axis = 3 : i32, fused_activation_function = "NONE"}> :
    // CHECK-ROUNDTRIP-SAME:    (tensor<4x3x5x1xi32>, tensor<4x3x5x1xi32>, tensor<4x3x5x2xi32>) -> tensor<4x3x5x4xi32>
    // CHECK-ROUNDTRIP:       %[[gather:.*]] = "stablehlo.gather"(%arg0, %[[concat]]) <{
    // CHECK-ROUNDTRIP-SAME:    dimension_numbers = #stablehlo.gather<
    // CHECK-ROUNDTRIP-SAME:      offset_dims = [3], collapsed_slice_dims = [0, 1, 2, 3],
    // CHECK-ROUNDTRIP-SAME:      start_index_map = [0, 2, 1, 3], index_vector_dim = 3>,
    // CHECK-ROUNDTRIP-SAME:    slice_sizes = array<i64: 1, 1, 1, 1, 8>}> :
    // CHECK-ROUNDTRIP-SAME:    (tensor<3x2x4x7x9xi32>, tensor<4x3x5x4xi32>) -> tensor<4x3x5x8xi32>
    // CHECK-ROUNDTRIP:       return %[[gather]]
    %0 = "stablehlo.gather"(%arg0, %arg1) {
      dimension_numbers = #stablehlo.gather<
        offset_dims = [3],
        collapsed_slice_dims = [1, 3],
        operand_batching_dims = [0, 2],
        start_indices_batching_dims = [1, 0],
        start_index_map = [1, 3],
        index_vector_dim = 3
      >,
      slice_sizes = array<i64: 1, 1, 1, 1, 8>,
      indices_are_sorted = false
    } : (tensor<3x2x4x7x9xi32>, tensor<4x3x5x2xi32>) -> tensor<4x3x5x8xi32>
    return %0 : tensor<4x3x5x8xi32>
  }
}