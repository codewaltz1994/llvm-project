// RUN: mlir-opt --test-transform-dialect-interpreter %s -split-input-file -verify-diagnostics | FileCheck %s

// Test One-Shot Bufferize.

transform.sequence failures(propagate) {
^bb0(%arg1: !pdl.operation):
  %0 = transform.structured.match ops{["func.func"]} in %arg1 : (!pdl.operation) -> !pdl.operation
  %1 = transform.bufferization.one_shot_bufferize %0 : (!pdl.operation) -> !pdl.operation
}

// CHECK-LABEL: func @test_function(
//  CHECK-SAME:     %[[A:.*]]: tensor<?xf32>
func.func @test_function(%A : tensor<?xf32>, %v : vector<4xf32>) -> (tensor<?xf32>) {
  %c0 = arith.constant 0 : index

  // CHECK: %[[A_memref:.*]] = bufferization.to_memref %[[A]]
  // CHECK: %[[dim:.*]] = memref.dim %[[A_memref]]
  // CHECK: %[[alloc:.*]] = memref.alloc(%[[dim]])
  // CHECK: memref.copy %[[A_memref]], %[[alloc]]
  // CHECK: vector.transfer_write %{{.*}}, %[[alloc]]
  // CHECK: %[[res_tensor:.*]] = bufferization.to_tensor %[[alloc]]
  %0 = vector.transfer_write %v, %A[%c0] : vector<4xf32>, tensor<?xf32>

  // CHECK: memref.dealloc %[[alloc]]
  // CHECK: return %[[res_tensor]]
  return %0 : tensor<?xf32>
}

// -----

// Test analysis of One-Shot Bufferize only.

transform.sequence failures(propagate) {
^bb0(%arg1: !pdl.operation):
  %0 = transform.structured.match ops{["func.func"]} in %arg1 : (!pdl.operation) -> !pdl.operation
  %1 = transform.bufferization.one_shot_bufferize %0
      {test_analysis_only = true} : (!pdl.operation) -> !pdl.operation
}

// CHECK-LABEL: func @test_function_analysis(
//  CHECK-SAME:     %[[A:.*]]: tensor<?xf32>
func.func @test_function_analysis(%A : tensor<?xf32>, %v : vector<4xf32>) -> (tensor<?xf32>) {
  %c0 = arith.constant 0 : index
  // CHECK: vector.transfer_write
  // CHECK-SAME: {__inplace_operands_attr__ = ["none", "false", "none"]}
  // CHECK-SAME: tensor<?xf32>
  %0 = vector.transfer_write %v, %A[%c0] : vector<4xf32>, tensor<?xf32>
  return %0 : tensor<?xf32>
}

// -----

// Test One-Shot Bufferize transform failure with an unknown op. This would be
// allowed with `allow_unknown_ops`.

transform.sequence failures(propagate) {
^bb0(%arg1: !pdl.operation):
  %0 = transform.structured.match ops{["func.func"]} in %arg1 : (!pdl.operation) -> !pdl.operation
  // expected-error @+1 {{bufferization failed}}
  %1 = transform.bufferization.one_shot_bufferize %0 : (!pdl.operation) -> !pdl.operation
}

func.func @test_unknown_op_failure() -> (tensor<?xf32>) {
  // expected-error @+1 {{op was not bufferized}}
  %0 = "test.dummy_op"() : () -> (tensor<?xf32>)
  return %0 : tensor<?xf32>
}

// -----

transform.sequence failures(propagate) {
^bb0(%arg1: !pdl.operation):
  // %arg1 is the module
  %0 = transform.bufferization.one_shot_bufferize %arg1 : (!pdl.operation) -> !pdl.operation
}

module {
  // CHECK-LABEL: func @test_function(
  //  CHECK-SAME:     %[[A:.*]]: tensor<?xf32>
  func.func @test_function(%A : tensor<?xf32>, %v : vector<4xf32>) -> (tensor<?xf32>) {
    %c0 = arith.constant 0 : index

    // CHECK: %[[A_memref:.*]] = bufferization.to_memref %[[A]]
    // CHECK: %[[dim:.*]] = memref.dim %[[A_memref]]
    // CHECK: %[[alloc:.*]] = memref.alloc(%[[dim]])
    // CHECK: memref.copy %[[A_memref]], %[[alloc]]
    // CHECK: vector.transfer_write %{{.*}}, %[[alloc]]
    // CHECK: %[[res_tensor:.*]] = bufferization.to_tensor %[[alloc]]
    %0 = vector.transfer_write %v, %A[%c0] : vector<4xf32>, tensor<?xf32>

    // CHECK: memref.dealloc %[[alloc]]
    // CHECK: return %[[res_tensor]]
    return %0 : tensor<?xf32>
  }
}

// -----

// Test we use identity layout at function boundaries.

transform.sequence failures(propagate) {
  ^bb0(%arg1: !pdl.operation):
  %0 = transform.bufferization.one_shot_bufferize layout{IdentityLayoutMap} %arg1
    { bufferize_function_boundaries = true } : (!pdl.operation) -> !pdl.operation
}

// CHECK: func.func @matmul(
// CHECK-SAME:  %[[A:.*]]: memref<12x9xf32>,
// CHECK-SAME:  %[[B:.*]]: memref<9x6xf32>,
// CHECK-SAME:  %[[C:.*]]: memref<12x6xf32>) -> memref<12x6xf32> {
func.func @matmul(%A: tensor<12x9xf32>, %B: tensor<9x6xf32>, %C: tensor<12x6xf32>) -> tensor<12x6xf32> {
  // CHECK: linalg.matmul ins(%[[A]], %[[B]] : memref<12x9xf32>, memref<9x6xf32>) outs(%[[C]] : memref<12x6xf32>)
  %D = linalg.matmul ins(%A, %B: tensor<12x9xf32>, tensor<9x6xf32>) outs(%C: tensor<12x6xf32>) -> tensor<12x6xf32>
  // CHECK: return %[[C]] : memref<12x6xf32>
  return %D : tensor<12x6xf32>
}

// -----

transform.sequence failures(propagate) {
  ^bb0(%arg1: !pdl.operation):
    %0 = transform.structured.match ops{["tensor.empty"]} in %arg1 : (!pdl.operation) -> !pdl.operation
    %1 = transform.cast %0 : !pdl.operation to !transform.op<"tensor.empty">
    transform.bufferization.empty_tensor_to_alloc_tensor %1 : (!transform.op<"tensor.empty">) -> !transform.op<"bufferization.alloc_tensor">
}

// Expect `bufferization.empty_tensor_to_alloc_tensor` to replace the tensor.empty.
func.func @empty_to_tensor_alloc() -> tensor<2x2xf32> {
  // CHECK: bufferization.alloc_tensor
  %0 = tensor.empty() : tensor<2x2xf32>
  return %0 : tensor<2x2xf32>
}
