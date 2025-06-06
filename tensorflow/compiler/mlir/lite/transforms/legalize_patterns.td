/* Copyright 2019 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/

// TFLite legalization patterns

include "mlir/IR/OpBase.td"
include "mlir/IR/PatternBase.td"
include "mlir/Dialect/Arith/IR/ArithOps.td"
include "mlir/Dialect/Func/IR/FuncOps.td"
include "tensorflow/compiler/mlir/lite/ir/tfl_ops.td"
include "tensorflow/compiler/mlir/tensorflow/ir/tf_ops.td"
include "tensorflow/compiler/mlir/lite/utils/utils.td"

def CreateEmptyBoolAttr : NativeCodeCall<"::mlir::BoolAttr()">;

def DenseElementsAttr : ElementsAttrBase<
  CPred<"llvm::isa<DenseElementsAttr>($_self)">,
  "non-opaque constant tensor">;

def F32ElementsAttr : ElementsAttrBase<
  CPred<"llvm::cast<ElementsAttr>($_self).getShapedType().getElementType().isF32()">, "float constant tensor">;

def Int64ElementsAttr : ElementsAttrBase<
  CPred<"llvm::cast<ElementsAttr>($_self).getShapedType().getElementType().isInteger(64)">, "Int 64 constant tensor">;

// Extract the ith int element from an ArrayAttr $0 as an 32-bit IntegerAttr
// with builder.
class ExtractI32At<int i> : NativeCodeCall<
    "$_builder.getI32IntegerAttr(llvm::cast<IntegerAttr>(llvm::cast<ArrayAttr>($_self).getValue()[" # i #
    "]).getInt())">;

// Use the tensor type information from $0 and convert min $1, max $2 and
// numBits $3 and narrowRange $4 to a QuantizedType.
def ConvertToQuantTypeFromAttrs : NativeCodeCall<
    "GetQuantizedTypeAttr($_builder, $0.getType(), $1, $2, -1, $3, $4, /*is_signed=*/false)">;

// Converts an integer attribute $0 to 32-bit with builder.
def convertIntAttrTo32Bit : NativeCodeCall<
    "$_builder.getI32IntegerAttr(llvm::cast<IntegerAttr>($0).getInt())">;

// Builds a constant bool attribute.
class GetBoolAttr<int value> :
    NativeCodeCall<"$_builder.getBoolAttr(" # value #")">;

// Converts an integer attribute $0 to 64-bit with builder.
def convertIntAttrTo64Bit : NativeCodeCall<
    "$_builder.getI64IntegerAttr(llvm::cast<IntegerAttr>($0).getInt())">;

// Extracts the single integer element from $_self.
def ExtractSingleElementAsInteger : NativeCodeCall<
    "ExtractSingleElementAsInteger(llvm::cast<ElementsAttr>($_self))">;

// Extracts the single int32 element from $_self.
def ExtractSingleElementAsInt32 : NativeCodeCall<
    "$_builder.getI32IntegerAttr(ExtractSingleElementAsInteger(llvm::cast<ElementsAttr>($_self)).getInt())">;

// Converts tensor with int64 to int32.
def CreateTFCastToInt32Op : NativeCodeCall<
  "CreateCastToInt32($0, $_loc, $_builder)">;

def CreateInt32ConstOrCast : NativeCodeCall<
  "CreateInt32ConstOrCast($0, $_loc, $_builder)">;

// Creates an int32 constant op from an integer attribute $0.
def CreateInt32ConstOpFromIntAttr
  : NativeCodeCall<"$_builder.create<TF::ConstOp>($_loc, DenseElementsAttr::get(RankedTensorType::get({}, $_builder.getI32Type()), {static_cast<int32_t>(llvm::cast<IntegerAttr>($0).getInt())}))">;

//===----------------------------------------------------------------------===//
// Nullary ops patterns.
//===----------------------------------------------------------------------===//

def createConstOp
  : NativeCodeCall<"$_builder.create<ConstOp>($_loc, $0.getType(), $1)">;

def LegalizeTFConstToTFLConst: Pat<(TF_ConstOp:$res ElementsAttr:$value),
                                   (createConstOp $res, $value)>;

// Convert to std constant for statically shaped, non-opaque constants.
def ConvertTfConstToStdConst : Pat<
  (TF_ConstOp:$res DenseElementsAttr:$value),
  (Arith_ConstantOp $value),
  [(AnyStaticShapeTensor $res)], [], (addBenefit 10)>;

//===----------------------------------------------------------------------===//
// Unary ops patterns.
//===----------------------------------------------------------------------===//
def IsDataFormatNHWC : ConstantAttr<TF_ConvnetDataFormatAttr, "\"NHWC\"">;
def IsDataFormatNCHW : ConstantAttr<TF_ConvnetDataFormatAttr, "\"NCHW\"">;

class I32VectorElementsAttr<int len> : ElementsAttrBase<
  CPred<"llvm::isa<DenseIntElementsAttr>($_self) &&"
      "llvm::cast<DenseIntElementsAttr>($_self).getType()."
      "getElementType().isSignlessInteger(32)">,
  "32-bit int elements attribute of shape [" # len # "]"> {

  let storageType = [{ DenseIntElementsAttr }];
  let returnType = [{ DenseIntElementsAttr }];

  let constBuilderCall = "DenseElementsAttr::get("
    "RankedTensorType::get({" # len # "}, $_builder.getIntegerType(32)), $0)";
}

// Constraint that Attr has values [1, X, Y, 1]
def IsIntList1XY1 : AttrConstraint<CPred<"TFIntListIs1XY1($_self)">>;

// Constraint that Attr has values [1, 1, X, Y]
def IsIntList11XY : AttrConstraint<CPred<"TFIntListIs11XY($_self)">>;

// Constraint that values in list attribute are all ones.
def IsAllOnes : AttrConstraint<CPred<"TFIntListIsAllOnes($_self)">>;

// Constraint that attribute is string with value either "SAME" or "VALID"
def IsSameOrValid : AttrConstraint<
    CPred<"llvm::cast<StringAttr>($_self).getValue() == \"SAME\" || " #
          "llvm::cast<StringAttr>($_self).getValue() == \"VALID\"">,
    "'SAME' or 'VALID' paddings">;

def TFL_GetMirrorPaddingType : NativeCodeCall<
    "mlir::TFL::MirrorPaddingTypeAttr::get($_builder.getContext(), " #
        "GetTFLMirrorPaddingFromString($0));">;

def LegalizeAbs : Pat<(TF_AbsOp $arg), (TFL_AbsOp $arg)>;
def LegalizeAddN : Pat<(TF_AddNOp $inputs), (TFL_AddNOp $inputs)>;

def LegalizeAveragePool : Pat<(TF_AvgPoolOp $value,
              IsIntList1XY1:$ksize,
              IsIntList1XY1:$strides,
              $padding,
              IsDataFormatNHWC:$format),
          (TFL_AveragePool2DOp $value,
              /*filter_height=*/ExtractI32At<1>:$ksize,
              /*filter_width=*/ExtractI32At<2>:$ksize,
              /*padding=*/$padding,
              /*stride_h=*/ExtractI32At<1>:$strides,
              /*stride_w=*/ExtractI32At<2>:$strides,
              /*fused_activation_function=*/TFL_AF_None)>;

def LegalizeNCHWAveragePool : Pat<(
              TF_AvgPoolOp:$src_op
              $value,
              IsIntList11XY:$ksize,
              IsIntList11XY:$strides,
              $padding,
              IsDataFormatNCHW:$format),
          (TFL_TransposeOp
            (TFL_AveragePool2DOp
              (TFL_TransposeOp $value,
                (Arith_ConstantOp
                  ConstantAttr<I32VectorElementsAttr<4>, "{0, 2, 3, 1}">)),
              /*filter_height=*/ExtractI32At<2>:$ksize,
              /*filter_width=*/ExtractI32At<3>:$ksize,
              /*padding=*/$padding,
              /*stride_h=*/ExtractI32At<2>:$strides,
              /*stride_w=*/ExtractI32At<3>:$strides,
              /*fused_activation_function=*/TFL_AF_None,
              (returnType (GetTransposedType<"{0, 2, 3, 1}"> $src_op))),
              (Arith_ConstantOp
                  ConstantAttr<I32VectorElementsAttr<4>, "{0, 3, 1, 2}">))>;

def LegalizeArgMax : Pat<(TF_ArgMaxOp $input, $dim),
                         (TFL_ArgMaxOp $input, $dim)>;
def LegalizeArgMin : Pat<(TF_ArgMinOp $input, $dim),
                         (TFL_ArgMinOp $input, $dim)>;

def LegalizeBroadcastTo : Pat<(TF_BroadcastToOp $input, $dim),
                              (TFL_BroadcastToOp $input, $dim)>;

def LegalizeCeil : Pat<(TF_CeilOp $arg), (TFL_CeilOp $arg)>;

def LegalizeCos : Pat<(TF_CosOp $arg), (TFL_CosOp $arg)>;

def LegalizeElu : Pat<(TF_EluOp $arg), (TFL_EluOp $arg)>;

def LegalizeExpandDims : Pat<(TF_ExpandDimsOp $input, $dim),
                             (TFL_ExpandDimsOp $input, $dim)>;

def LegalizeFakeQuantToDequantizeQuantize : Pat<
  (TF_FakeQuantWithMinMaxArgsOp $inputs, $min, $max, $num_bits, $narrow_range),
  (TFL_DequantizeOp
   (TFL_QuantizeOp $inputs,
                   (ConvertToQuantTypeFromAttrs $inputs, $min, $max,
                    $num_bits, $narrow_range)))>;

def LegalizeFill : Pat<(TF_FillOp $arg, $value), (TFL_FillOp $arg, $value)>;

def LegalizeFloor : Pat<(TF_FloorOp $arg), (TFL_FloorOp $arg)>;

def LegalizeLeakyRelu : Pat<(TF_LeakyReluOp $arg, F32Attr:$a),
                            (TFL_LeakyReluOp $arg, $a)>;

def LegalizeLog : Pat<(TF_LogOp $arg), (TFL_LogOp $arg)>;

def LegalizeLog1p : Pat<
  (TF_Log1pOp F32Tensor:$arg),
  (TFL_LogOp (TFL_AddOp $arg,
                  (Arith_ConstantOp ConstantAttr<RankedF32ElementsAttr<[]>, "1.0f">),
                  TFL_AF_None))>;

def LegalizeNot : Pat<(TF_LogicalNotOp $arg), (TFL_LogicalNotOp $arg)>;

def LegalizeLogSoftmax : Pat<(TF_LogSoftmaxOp $arg), (TFL_LogSoftmaxOp $arg)>;

def LegalizeMaxPool2D : Pat<
          (TF_MaxPoolOp $value,
              IsIntList1XY1:$ksize,
              IsIntList1XY1:$strides,
              $padding,
              $explicit_paddings,
              IsDataFormatNHWC:$format),
          (TFL_MaxPool2DOp $value,
              /*padding=*/$padding,
              /*stride_w=*/ExtractI32At<2>:$strides,
              /*stride_h=*/ExtractI32At<1>:$strides,
              /*filter_width=*/ExtractI32At<2>:$ksize,
              /*filter_height=*/ExtractI32At<1>:$ksize,
              /*fused_activation_function=*/TFL_AF_None)>;

def LegalizeNCHWMaxPool2D : Pat<
          (TF_MaxPoolOp:$src_op
              $value,
              IsIntList11XY:$ksize,
              IsIntList11XY:$strides,
              $padding,
              $explicit_paddings,
              IsDataFormatNCHW:$format),
          (TFL_TransposeOp
            (TFL_MaxPool2DOp
              (TFL_TransposeOp $value,
                (Arith_ConstantOp
                  ConstantAttr<I32VectorElementsAttr<4>, "{0, 2, 3, 1}">)),
              /*padding=*/$padding,
              /*stride_w=*/ExtractI32At<3>:$strides,
              /*stride_h=*/ExtractI32At<2>:$strides,
              /*filter_width=*/ExtractI32At<3>:$ksize,
              /*filter_height=*/ExtractI32At<2>:$ksize,
              /*fused_activation_function=*/TFL_AF_None,
              (returnType (GetTransposedType<"{0, 2, 3, 1}"> $src_op))),
            (Arith_ConstantOp
              ConstantAttr<I32VectorElementsAttr<4>, "{0, 3, 1, 2}">))>;

def LegalizeMaximum : Pat<(TF_MaximumOp $arg1, $arg2),
                          (TFL_MaximumOp $arg1, $arg2)>;

def LegalizeMinimum : Pat<(TF_MinimumOp $arg1, $arg2),
                          (TFL_MinimumOp $arg1, $arg2)>;

def LegalizeNeg : Pat<(TF_NegOp $arg), (TFL_NegOp $arg)>;
def LegalizeOneHot : Pat<
  (TF_OneHotOp $indices, $depth, $on_value, $off_value, $axis),
  (TFL_OneHotOp $indices, $depth, $on_value, $off_value,
  (convertIntAttrTo32Bit $axis))>;
def LegalizePow : Pat<(TF_PowOp $x, $y), (TFL_PowOp $x, $y)>;
def LegalizeRange : Pat<(TF_RangeOp $start, $limit, $delta),
                        (TFL_RangeOp $start, $limit, $delta)>;
def LegalizeRelu6 : Pat<(TF_Relu6Op $arg), (TFL_Relu6Op $arg)>;
def LegalizeRelu : Pat<(TF_ReluOp $arg), (TFL_ReluOp $arg)>;
// TFL Relu doesn't support I32/I64 type, so legalizes TF Relu to TFL Maximum.
def LegalizeReluI32 :
  Pat<(TF_ReluOp TensorOf<[I32]>:$arg),
      (TFL_MaximumOp $arg,
        (Arith_ConstantOp ConstantAttr<RankedI32ElementsAttr<[]>,"0">))>;
def LegalizeReluI64 :
  Pat<(TF_ReluOp TensorOf<[I64]>:$arg),
      (TFL_MaximumOp $arg,
        (Arith_ConstantOp
          ConstantAttr<RankedI64ElementsAttr<[]>,"static_cast<int64_t>(0)">))>;
def LegalizeReverseSequence : Pat<
  (TF_ReverseSequenceOp $input, $seq_lengths, $seq_dim, $batch_dim),
  (TFL_ReverseSequenceOp $input, $seq_lengths,
      (convertIntAttrTo32Bit $seq_dim), (convertIntAttrTo32Bit $batch_dim))>;
def LegalizeRound : Pat<(TF_RoundOp $arg), (TFL_RoundOp $arg)>;
def LegalizeRsqrt : Pat<(TF_RsqrtOp $arg), (TFL_RsqrtOp $arg)>;
def LegalizeSqrt : Pat<(TF_SqrtOp $arg), (TFL_SqrtOp $arg)>;
def LegalizeSquare : Pat<(TF_SquareOp $arg), (TFL_SquareOp $arg)>;
def LegalizeSegmentSum : Pat<(TF_SegmentSumOp $data, $segment_ids),
                             (TFL_SegmentSumOp $data, (CreateTFCastToInt32Op $segment_ids))>;
foreach UnsortedSegmentOp = [
  [TF_UnsortedSegmentSumOp, TFL_UnsortedSegmentSumOp],
  [TF_UnsortedSegmentMaxOp, TFL_UnsortedSegmentMaxOp],
  [TF_UnsortedSegmentMinOp, TFL_UnsortedSegmentMinOp],
  [TF_UnsortedSegmentProdOp, TFL_UnsortedSegmentProdOp]] in {
  def Legalize#UnsortedSegmentOp[0] :
     Pat<(UnsortedSegmentOp[0] $data, $segment_ids, $num_segments),
              (UnsortedSegmentOp[1] $data, (CreateTFCastToInt32Op $segment_ids),
                  (CreateTFCastToInt32Op $num_segments))>;
}
def LegalizeSelect : Pat<(TF_SelectOp $cond, $x, $y),
                         (TFL_SelectOp $cond, $x, $y)>;
def LegalizeSelectV2SameStaticShape : Pat<(TF_SelectV2Op:$src_op $cond, $x, $y),
    (TFL_SelectOp $cond, $x, $y),
    [(OpHasSameStaticShapes $src_op)]>;
def LegalizeSelectV2NotSameStaticShape : Pat<
  (TF_SelectV2Op:$src_op $cond, $x, $y),
  (TFL_SelectV2Op $cond, $x, $y),
  [(OpHasNotSameStaticShapes $src_op)]>;
def LegalizeShape : Pat<(TF_ShapeOp $arg), (TFL_ShapeOp $arg)>;
def LegalizeSigmoid : Pat<(TF_SigmoidOp $arg), (TFL_LogisticOp $arg)>;
def LegalizeSin : Pat<(TF_SinOp $arg), (TFL_SinOp $arg)>;
def LegalizeSlice : Pat<(TF_SliceOp $input, $begin, $size),
                        (TFL_SliceOp $input, $begin, $size)>;
def LegalizeSoftmax : Pat<(TF_SoftmaxOp $arg),
                          (TFL_SoftmaxOp $arg, ConstF32Attr<"1.0">)>;
def LegalizeSoftPlus : Pat<(TF_SoftplusOp F32Tensor:$arg0),
    (TFL_LogOp (TFL_AddOp (TFL_ExpOp $arg0),
                (Arith_ConstantOp ConstantAttr<RankedF32ElementsAttr<[]>, "1.0f">),
                TFL_AF_None))>;
def LegalizeSqueeze : Pat<(TF_SqueezeOp $arg, $squeeze_dims),
                          (TFL_SqueezeOp $arg, $squeeze_dims)>;
def LegalizeTanh : Pat<(TF_TanhOp $arg), (TFL_TanhOp $arg)>;

def LegalizeTranspose : Pat<(TF_TransposeOp $arg, $perm),
                            (TFL_TransposeOp $arg,
                            (CreateTFCastToInt32Op $perm))>;

def LegalizeWhere : Pat<(TF_WhereOp $arg), (TFL_WhereOp $arg)>;
def LegalizeZerosLike : Pat<(TF_ZerosLikeOp $arg), (TFL_ZerosLikeOp $arg)>;

def LegalizeBroadcastArgs : Pat<(TF_BroadcastArgsOp $s0, $s1),
                                (TFL_BroadcastArgsOp $s0, $s1)>;

//===----------------------------------------------------------------------===//
// Binary ops patterns.
//===----------------------------------------------------------------------===//
def LegalizeLess : Pat<(TF_LessOp $l, $r), (TFL_LessOp $l, $r)>;
def LegalizeGreater : Pat<(TF_GreaterOp $l, $r), (TFL_GreaterOp $l, $r)>;

def LegalizeLessEqual : Pat<(TF_LessEqualOp $l, $r), (TFL_LessEqualOp $l, $r)>;
def LegalizeGreaterEqual : Pat<(TF_GreaterEqualOp $l, $r),
                               (TFL_GreaterEqualOp $l, $r)>;

// Gather in TF -> Gather in TFL with axis=0
// The 'validate_indices' attribute is deprecated.
def LegalizeGather: Pat<
  (TF_GatherOp $params, $indices, $ignored_validate_indices),
  (TFL_GatherOp $params, $indices, ConstantAttr<I32Attr, "0">,
     ConstantAttr<I32Attr, "0">)>;

def LegalizeGatherNd : Pat<(TF_GatherNdOp $params, $indices, $bad_indices_policy),
                           (TFL_GatherNdOp $params, $indices)>;

def LegalizeGatherV2 : Pat<
  (TF_GatherV2Op $params, $indices, (Arith_ConstantOp ElementsAttr:$axis), $batch_dims),
  (TFL_GatherOp $params, $indices, ExtractSingleElementAsInt32:$axis,
    (convertIntAttrTo32Bit $batch_dims))>;

def LegalizeFloorDiv : Pat<(TF_FloorDivOp $l, $r), (TFL_FloorDivOp $l, $r)>;

def LegalizeNotEqual : Pat<
  (TF_NotEqualOp $l, $r, /*incompatible_shape_error=*/ConstBoolAttrTrue),
  (TFL_NotEqualOp $l, $r)>;

def LegalizeLogicalAnd : Pat<(TF_LogicalAndOp $l, $r),
                             (TFL_LogicalAndOp $l, $r)>;

def LegalizeLogicalOr : Pat<(TF_LogicalOrOp $l, $r), (TFL_LogicalOrOp $l, $r)>;

def LegalizeAdd : Pat<(TF_AddOp $lhs, $rhs),
                      (TFL_AddOp $lhs, $rhs, TFL_AF_None)>;
def LegalizeAddv2 : Pat<(TF_AddV2Op $lhs, $rhs),
                        (TFL_AddOp $lhs, $rhs, TFL_AF_None)>;
def LegalizeBiasAdd : Pat<
  (TF_BiasAddOp F32Tensor:$l, F32Tensor:$r, IsDataFormatNHWC:$data_format),
  (TF_AddV2Op $l, $r)>;
def LegalizeSub : Pat<(TF_SubOp $lhs, $rhs),
                      (TFL_SubOp $lhs, $rhs, TFL_AF_None)>;
def LegalizeMul : Pat<(TF_MulOp $lhs, $rhs),
                      (TFL_MulOp $lhs, $rhs, TFL_AF_None)>;
def LegalizeRealDiv : Pat<(TF_RealDivOp $lhs, $rhs),
                          (TFL_DivOp $lhs, $rhs, TFL_AF_None)>;
def LegalizeDiv : Pat<(TF_DivOp $lhs, $rhs),
                      (TFL_DivOp $lhs, $rhs, TFL_AF_None)>;

// When batch size is known, TF BatchMatMul gets unfolded to TFL FullyConnected
// with additional ops. In the case of unknown batch size, the match will
// fall through to here and convert to TF Lite BatchMatMul.
// TODO(b/207064634): CreateEmptyBoolAttr is a temporary workaround for this bug.
def LegalizeBatchMatMulV3UnknownBatch : Pat<
  (TF_BatchMatMulV3Op $lhs, $rhs, $adj_x, $adj_y, $grad_x, $grad_y),
  (TFL_BatchMatMulOp $lhs, $rhs, $adj_x, $adj_y, CreateEmptyBoolAttr:$adj_y)>;
def LegalizeBatchMatMulV2UnknownBatch : Pat<
  (TF_BatchMatMulV2Op $lhs, $rhs, $adj_x, $adj_y, $grad_x, $grad_y),
  (TFL_BatchMatMulOp $lhs, $rhs, $adj_x, $adj_y, CreateEmptyBoolAttr:$adj_y)>;
def LegalizeBatchMatMulUnknownBatch : Pat<
  (TF_BatchMatMulOp $lhs, $rhs, $adj_x, $adj_y, $grad_x, $grad_y),
  (TFL_BatchMatMulOp $lhs, $rhs, $adj_x, $adj_y, CreateEmptyBoolAttr:$adj_y)>;

def LegalizeFakeQuantWithMinMaxVars: Pat<
  (TF_FakeQuantWithMinMaxVarsOp $inputs, (Arith_ConstantOp F32ElementsAttr:$min),
    (Arith_ConstantOp F32ElementsAttr:$max), $num_bits, $narrow_range),
  (TFL_DequantizeOp
    (TFL_QuantizeOp $inputs, (ConvertToQuantTypeFromAttrs $inputs, $min, $max,
                              $num_bits, $narrow_range)))>;

// TODO(rocky): Not all of the attributes are handled correctly.  Make this
// more general if there is a need.
def LegalizeQuantizeAndDequantizeV4 : Pat<
  (TF_QuantizeAndDequantizeV4Op $inputs, (Arith_ConstantOp F32ElementsAttr:$min),
    (Arith_ConstantOp F32ElementsAttr:$max),
    $signed_input, $num_bits, $range_given, $round_mode, $narrow_range, $axis),
  (TFL_DequantizeOp
    (TFL_QuantizeOp $inputs, (ConvertToQuantTypeFromAttrs $inputs, $min, $max,
                              $num_bits, $narrow_range)))>;

def LegalizeRank : Pat<(TF_RankOp $input), (TFL_RankOp $input)>;

def LegalizeSquaredDifference : Pat<(TF_SquaredDifferenceOp $l, $r),
                                    (TFL_SquaredDifferenceOp $l, $r)>;

def LegalizeReverseV2 : Pat<
  (TF_ReverseV2Op $arg0, $axis),
  (TFL_ReverseV2Op $arg0, (CreateTFCastToInt32Op $axis))>;

def LegalizeEqual : Pat<(TF_EqualOp $arg0, $arg1,
                          /*incompatible_shape_error=*/ConstBoolAttrTrue),
                        (TFL_EqualOp $arg0, $arg1)>;

def LegalizePad : Pat<(TF_PadOp $arg0, $arg1), (TFL_PadOp $arg0, $arg1)>;

def LegalizeTile : Pat<(TF_TileOp $arg0, $arg1), (TFL_TileOp $arg0, $arg1)>;

def LegalizePadV2 : Pat<(TF_PadV2Op $arg0, $arg1, $cst),
                        (TFL_PadV2Op $arg0, $arg1, $cst)>;

def LegalizeMean : Pat<(TF_MeanOp $arg0, $arg1, BoolAttr:$arg2),
                       (TFL_MeanOp $arg0, $arg1, $arg2)>;

def LegalizeSum : Pat<(TF_SumOp $arg, $axes, BoolAttr:$arg2),
                      (TFL_SumOp $arg, (CreateTFCastToInt32Op $axes), $arg2)>;

// TopK in TFL is always sorted so we ignore that attribute here.
def LegalizeTopKV2 : Pat<(TF_TopKV2Op $input, $k, $ignored_sorted),
                         (TFL_TopKV2Op $input, $k)>;

def ReductionDimensionIsLastDim : Constraint<CPred<"(llvm::cast<IntegerAttr>($0).getInt() == "
  "llvm::cast<ShapedType>($1.getType()).getRank() - 1 || llvm::cast<IntegerAttr>($0).getInt() == -1)">>;

// Legalizes TF_ApproxTopKOp to TFL_TopKV2Op with the following constraints:
//    1. It computes max k
//    2. The reduction dimension is the last dim of the input.
def LegalizeApproxTopK : Pat<(TF_ApproxTopKOp $input, $k, $reduction_dimenstion, $ignored_recall_target, /*is_max_k*/ConstBoolAttrTrue, $ignored_reduction_input_size_override, $ignored_aggregate_to_topk),
                         (TFL_TopKV2Op $input, (CreateInt32ConstOpFromIntAttr $k)),
                         [(ReductionDimensionIsLastDim $reduction_dimenstion, $input)]>;

def LegalizeMin : Pat<
  (TF_MinOp $arg0, $axes, BoolAttr:$arg2),
  (TFL_ReduceMinOp $arg0, (CreateTFCastToInt32Op $axes), $arg2)>;

def LegalizeMax : Pat<
  (TF_MaxOp $arg0, $axes, BoolAttr:$arg2),
  (TFL_ReduceMaxOp $arg0, (CreateTFCastToInt32Op $axes), $arg2)>;

def LegalizeProd : Pat<
  (TF_ProdOp $arg0, $axes, BoolAttr:$arg2),
  (TFL_ReduceProdOp $arg0, (CreateTFCastToInt32Op $axes), $arg2)>;

def LegalizeAny : Pat<
  (TF_AnyOp $input, $reduction_indices, $keep_dims),
  (TFL_ReduceAnyOp $input, (CreateTFCastToInt32Op $reduction_indices),
                   $keep_dims)>;

def LegalizeAll : Pat<
  (TF_AllOp $input, $reduction_indices, $keep_dims),
  (TFL_ReduceAllOp $input, (CreateTFCastToInt32Op $reduction_indices),
                   $keep_dims)>;

def LegalizeCast : Pat<(TF_CastOp $arg0, BoolAttr:$arg1), (TFL_CastOp $arg0)>;

def LegalizeBatchToSpaceND : Pat<
  (TF_BatchToSpaceNDOp $input, $block_shape, $crops),
  (TFL_BatchToSpaceNdOp $input, (CreateTFCastToInt32Op $block_shape),
     (CreateTFCastToInt32Op $crops))>;

def LegalizeSpaceToBatchND : Pat<
  (TF_SpaceToBatchNDOp $input, $block_shape, $paddings),
  (TFL_SpaceToBatchNdOp $input, (CreateTFCastToInt32Op $block_shape),
     (CreateTFCastToInt32Op $paddings))>;

def LegalizeSpaceToDepth : Pat<
  (TF_SpaceToDepthOp $input, $block_size, IsDataFormatNHWC:$data_format),
  (TFL_SpaceToDepthOp $input, (convertIntAttrTo32Bit $block_size))>;

def LegalizeDepthToSpace : Pat<
  (TF_DepthToSpaceOp $input, $block_size, IsDataFormatNHWC:$data_format),
  (TFL_DepthToSpaceOp $input, (convertIntAttrTo32Bit $block_size))>;

def LegalizeResizeBilinear : Pat<
  (TF_ResizeBilinearOp $images, $size, $align_corners, $half_pixel_centers),
  (TFL_ResizeBilinearOp $images, $size, $align_corners, $half_pixel_centers)>;
def LegalizeResizeNearestNeighbor : Pat<
  (TF_ResizeNearestNeighborOp $images, $size, $align_corners,
    $half_pixel_centers),
  (TFL_ResizeNearestNeighborOp $images, $size, $align_corners,
    $half_pixel_centers)>;

def LegalizeMirrorPad : Pat<(TF_MirrorPadOp $arg0, $arg1, $mode),
                            (TFL_MirrorPadOp $arg0, $arg1, (TFL_GetMirrorPaddingType $mode))>;

def LegalizeSparseToDense : Pat<
  (TF_SparseToDenseOp $sparse_indices, $output_shape, $sparse_values,
    $default_value, $validate_indices),
  (TFL_SparseToDenseOp $sparse_indices, $output_shape, $sparse_values,
    $default_value)>;

def LegalizeUnique : Pat<(TF_UniqueOp $arg0),(TFL_UniqueOp $arg0)>;

def LegalizeFloorMod : Pat<(TF_FloorModOp $arg0, $arg1),
                           (TFL_FloorModOp $arg0, $arg1)>;
def LegalizeExp : Pat<(TF_ExpOp $arg0), (TFL_ExpOp $arg0)>;

def LegalizeLRN : Pat<
  (TF_LRNOp $arg0, $radius, F32Attr:$bias, F32Attr:$alpha, F32Attr:$beta),
  (TFL_LocalResponseNormalizationOp $arg0, (convertIntAttrTo32Bit $radius),
    $bias, $alpha, $beta)>;

def LegalizeNonMaxSuppressionV4 : Pat<
  (TF_NonMaxSuppressionV4Op $boxes, $scores, $max_output_size, $iou_threshold,
    $score_threshold, $pad_to_max_output_size),
  (TFL_NonMaxSuppressionV4Op $boxes, $scores, $max_output_size, $iou_threshold,
    $score_threshold)>;

def LegalizeNonMaxSuppressionV5 : Pat<
  (TF_NonMaxSuppressionV5Op $boxes, $scores, $max_output_size, $iou_threshold,
    $score_threshold, $soft_nms_sigma, $pad_to_max_output_size),
  (TFL_NonMaxSuppressionV5Op $boxes, $scores, $max_output_size, $iou_threshold,
    $score_threshold, $soft_nms_sigma)>;

def LegalizeMatrixDiag : Pat<(TF_MatrixDiagOp $diagonal),
                             (TFL_MatrixDiagOp $diagonal)>;

def LegalizeConv2DBackpropInput : Pat<
  (TF_Conv2DBackpropInputOp $input_sizes, $filter, $out_backprop,
     IsIntList1XY1:$strides,
     BoolAttr:$use_cudnn_on_gpu,
     IsSameOrValid:$padding,
     I64ArrayAttr:$explicit_paddings,
     IsDataFormatNHWC:$data_format,
     IsAllOnes:$dilations),
  (TFL_TransposeConvOp $input_sizes,
     (TFL_TransposeOp $filter,
       (Arith_ConstantOp ConstantAttr<I32VectorElementsAttr<4>, "{2, 0, 1, 3}">)),
     $out_backprop,
     /*bias=*/ (CreateNoneValue $input_sizes),
     /*padding=*/ $padding,
     /*stride_h=*/ ExtractI32At<1>:$strides,
     /*stride_w=*/ ExtractI32At<2>:$strides,
     /*fused_activation_function=*/TFL_AF_None)>;

def IsRankZeroAttr
  : CPred<"llvm::cast<DenseElementsAttr>($_self).getType().getRank() == 0">;

def HasValueZero
  : CPred<"llvm::cast<DenseElementsAttr>($_self)."
          "getSplatValue<::mlir::IntegerAttr>().getInt() == 0">;

// TFLite only supports MatrixSetDiag ops with scalar zero k attribute.
def IsSupportedByTFLiteMatrixSetDiag
  : ElementsAttrBase<And<[ElementsAttr.predicate,
                          IsRankZeroAttr, HasValueZero]>,
                     "MatrixSetDiag attribute verification">;

// Attribute align doesn't matter when k is zero.
def LegalizeMatrixSetDiag : Pat<
  (TF_MatrixSetDiagV3Op $input, $diagonal,
    (ConstantLikeMatcher IsSupportedByTFLiteMatrixSetDiag:$k), $align),
  (TFL_MatrixSetDiagOp $input, $diagonal)>;

def LegalizeScatterNd : Pat<
  (TF_ScatterNdOp $indices, $updates, $shape, ConstantStrAttr<StrAttr, "">),
  (TFL_ScatterNdOp (CreateTFCastToInt32Op $indices), $updates,
    (CreateTFCastToInt32Op $shape))>;

def LegalizeScatterNdDefaultBadindicesPolicy : Pat<
  (TF_ScatterNdOp $indices, $updates, $shape, ConstantStrAttr<StrAttr, "DEFAULT">),
  (TFL_ScatterNdOp (CreateTFCastToInt32Op $indices), $updates,
    (CreateTFCastToInt32Op $shape))>;

def LegalizeScatterNdIgnoreBadIndices : Pat<
  (TF_ScatterNdOp $indices, $updates, $shape, ConstantStrAttr<StrAttr, "IGNORE">),
  (TFL_ScatterNdOp (CreateTFCastToInt32Op $indices), $updates,
    (CreateTFCastToInt32Op $shape))>;

def LegalizeCumsum : Pat<
  (TF_CumsumOp $input, $axis, $exclusive, $reverse),
  (TFL_CumsumOp $input, (CreateTFCastToInt32Op $axis), $exclusive, $reverse)>;

def LegalizeReshape : Pat<
  (TF_ReshapeOp $input, $shape),
  (TFL_ReshapeOp $input, (CreateInt32ConstOrCast $shape))>;

def LegalizeStridedSlice : Pat<
  (TF_StridedSliceOp
    $input, $begin, $end, $strides, $begin_mask, $end_mask,
    $ellipsis_mask, $new_axis_mask, $shrink_axis_mask),
  (TFL_StridedSliceOp $input,
    (CreateTFCastToInt32Op $begin), (CreateTFCastToInt32Op $end),
    (CreateTFCastToInt32Op $strides), (convertIntAttrTo32Bit $begin_mask),
    (convertIntAttrTo32Bit $end_mask), (convertIntAttrTo32Bit $ellipsis_mask),
    (convertIntAttrTo32Bit $new_axis_mask),
    (convertIntAttrTo32Bit $shrink_axis_mask),
    (GetBoolAttr<false>))>;

def LegalizeRfft2d : Pat<
  (TF_RFFT2DOp $input, $fft_length),
  (TFL_RFFT2dOp $input, $fft_length)>;

def LegalizeComplexAbs : Pat<(TF_ComplexAbsOp $arg), (TFL_ComplexAbsOp $arg)>;

def LegalizeReal : Pat<(TF_RealOp $arg), (TFL_RealOp $arg)>;

def LegalizeImag : Pat<(TF_ImagOp $arg), (TFL_ImagOp $arg)>;

def LegalizeBucketize : Pat<
  (TF_BucketizeOp $input, F32ArrayAttr:$boundaries),
  (TFL_BucketizeOp $input, $boundaries)>;

def LegalizeRandomUniform : Pat<
  (TF_RandomUniformOp $shape, $seed, $seed2),
  (TFL_RandomUniformOp $shape, (convertIntAttrTo64Bit $seed),
   (convertIntAttrTo64Bit $seed2))>;

def LegalizeRandomStandardNormal : Pat<
  (TF_RandomStandardNormalOp $shape, $seed, $seed2),
  (TFL_RandomStandardNormalOp $shape, (convertIntAttrTo64Bit $seed),
   (convertIntAttrTo64Bit $seed2))>;

def LegalizeMultinomial : Pat<
  (TF_MultinomialOp $logits, $num_samples, $seed, $seed2),
  (TFL_MultinomialOp $logits, $num_samples, (convertIntAttrTo64Bit $seed),
   (convertIntAttrTo64Bit $seed2))>;

def LegalizeXlaDynamicUpdateSlice : Pat<
  (TF_XlaDynamicUpdateSliceOp $operand, $update, $start_indices),
  (TFL_DynamicUpdateSliceOp $operand, $update, $start_indices)>;

def LegalizeAtan2 : Pat<(TF_Atan2Op $y, $x), (TFL_Atan2Op $y, $x)>;

def LegalizeSign : Pat<(TF_SignOp $x), (TFL_SignOp $x)>;

def LegalizeBitcast : Pat<(TF_BitcastOp $x), (TFL_BitcastOp $x)>;

def LegalizeBitwiseXor : Pat<(TF_BitwiseXorOp $l, $r),
                             (TFL_BitwiseXorOp $l, $r)>;

def LegalizeRightShift : Pat<(TF_RightShiftOp $l, $r),
                             (TFL_RightShiftOp $l, $r)>;

// =============================================================================
// Training OPs
// =============================================================================

// `grad = dy * y * (1 - y)`, where `y = sigmoid(x)`
def LegalizeSigmoidGrad : Pat<(TF_SigmoidGradOp $y, $dy),
  (TFL_MulOp $dy, (TFL_MulOp $y, (TFL_SubOp
        (Arith_ConstantOp ConstantAttr<RankedF32ElementsAttr<[]>, "1.0f">),
        $y, TFL_AF_None),
  TFL_AF_None), TFL_AF_None)>;

