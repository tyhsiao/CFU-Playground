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
#ifndef TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
#define TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_

#include "playground_util/print_params.h"
#include "tensorflow/lite/kernels/internal/common.h"
#include "cfu.h"
#include <iostream>
#include <algorithm>
#include <cstdio>
using namespace std;

namespace tflite {
namespace reference_integer_ops {

// Fixed-point per-channel-quantization convolution reference kernel.
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const int32_t* bias_data, const RuntimeShape& output_shape,
    int8_t* output_data) {
  // Get parameters.
  const int32_t input_offset = params.input_offset;  // r = s(q - Z)
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;
  const int32_t output_offset = params.output_offset;

  print_conv_params(params, input_shape, filter_shape, output_shape);

  // Set min and max value of the output.
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // Consistency check.
  TFLITE_DCHECK_LE(output_activation_min, output_activation_max);
  TFLITE_DCHECK_EQ(input_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(filter_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(output_shape.DimensionsCount(), 4);
  const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  if (bias_data) {
    TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  }

  // Check dimensions of the tensors.
  const int input_batches = input_shape.Dims(0);
  const int input_height  = input_shape.Dims(1);
  const int input_width   = input_shape.Dims(2);
  const int input_depth = input_shape.Dims(3);
  const int filter_output_depth = filter_shape.Dims(0);
  const int filter_height       = filter_shape.Dims(1);
  const int filter_width        = filter_shape.Dims(2);
  const int filter_input_depth  = filter_shape.Dims(3);
  const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);

  // Set Parameters to CFU
  cfu_op0(/* funct7= */ 6,/* in0= */  0, /* in1= */ 0);
  cfu_op0(/* funct7= */ 7,/* in0= */  input_offset, /* in1= */ 0);
  cfu_op0(/* funct7= */ 7,/* in0= */  input_batches, /* in1= */ input_height);
  cfu_op0(/* funct7= */ 7,/* in0= */  input_width, /* in1= */ input_depth);
  cfu_op0(/* funct7= */ 7,/* in0= */  filter_output_depth, /* in1= */ filter_height);
  cfu_op0(/* funct7= */ 7,/* in0= */  filter_width, /* in1= */ filter_input_depth);
  cfu_op0(/* funct7= */ 7,/* in0= */  dilation_width_factor, /* in1= */ dilation_height_factor);

  // Store Filter Data to ASIC
  int filter_size = 1;
  for(int i=0 ; i<4 ; i++) {
    filter_size *= filter_shape.Dims(i);
  }
  int filter_size_alone = filter_size % 8;
  int filter_size_slice = filter_size / 8;

  const int32_t* filter_32data = (int32_t*) filter_data;
  cfu_op0(/*funct7= */ 0, /* in0= */  0, /* in1= */ 0);
  for(int i=0, j=0 ; i<filter_size_slice; i++, j=j+2){ 
    cfu_op0(/* funct7= */ 1, /* in0= */ *(filter_32data + j), /* in1= */ *(filter_32data + 1 + j )); //func3=0
  }

  if( filter_size_alone != 0){
    int prefix_index = filter_size_slice * 8;
    for(int i=0 ; i<filter_size_alone ; i++){
      cfu_op0(/*funct7= */ 2, /* in0= */ (uint32_t)(*(filter_data + prefix_index + i)), /* in1= */ 0);
    }
  }

  // Store Input Data to ASIC
  int input_size = 1;
  for(int i=0 ; i<4 ; i++) {
    input_size *= input_shape.Dims(i);
  }
  int input_size_alone = input_size % 8;
  int input_size_slice = input_size / 8;

  const int32_t* input_32data = (int32_t*) input_data;
  cfu_op0(/*funct7= */ 3, /* in0= */  0, /* in1= */ 0);
  for(int i=0, j=0 ; i<input_size_slice; i++, j=j+2){ 
    cfu_op0(/* funct7= */ 4, /* in0= */ *(input_32data + j), /* in1= */ *(input_32data + 1 + j )); //func3=0
  }

  if( input_size_alone != 0){
    int prefix_index = input_size_slice * 8;
    for(int i=0 ; i<input_size_alone ; i++){
      cfu_op0(/*funct7= */ 5, /* in0= */ (uint32_t)(*(input_data + prefix_index + i)), /* in1= */ 0);
    }
  }


  for (int batch = 0; batch < batches; ++batch) {
    for (int out_y = 0; out_y < output_height; ++out_y) {
      const int in_y_origin = (out_y * stride_height) - pad_height;
      for (int out_x = 0; out_x < output_width; ++out_x) {
        const int in_x_origin = (out_x * stride_width) - pad_width;
        for (int out_channel = 0; out_channel < output_depth; ++out_channel) {
          auto group = out_channel / filters_per_group;
          
          // Set Param
          cfu_op0(/* funct7= */ 8, 0, 0); // Reset Param
          cfu_op0(/* funct7= */ 9, in_x_origin, in_y_origin); 
          cfu_op0(/* funct7= */ 9, batch, out_channel); 
          cfu_op0(/* funct7= */ 9, group, 0); 
          
          // Run Conv Acc
          int32_t acc = cfu_op0(/* funct7= */ 10, 0, 0); 

          // for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
          //   const int in_y = in_y_origin + dilation_height_factor * filter_y;
          //   for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
          //     const int in_x = in_x_origin + dilation_width_factor * filter_x;

          //     // Zero padding by omitting the areas outside the image.
          //     const bool is_point_inside_image =
          //         (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
          //         (in_y < input_height);

 

          //     if (!is_point_inside_image) {
          //       continue;
          //     }

          //     for (int in_channel = 0; in_channel < filter_input_depth; ++in_channel) {
          //       int32_t input_val = input_data[Offset(input_shape, batch, in_y, in_x, in_channel + group * filter_input_depth)];
          //       uint32_t filter_index = Offset(filter_shape, out_channel, filter_y, filter_x, in_channel);
          //       acc = (int32_t)cfu_op0(/* funct7= */ 3, /* in0= */ input_val, filter_index);
          //       // acc += filter_val * (input_val + input_offset);
          //     }


          //   }
          // }

          if (bias_data) {
            acc += bias_data[out_channel];
          }
          acc = MultiplyByQuantizedMultiplier(
              acc, output_multiplier[out_channel], output_shift[out_channel]);
          acc += output_offset;
          acc = std::max(acc, output_activation_min);
          acc = std::min(acc, output_activation_max);
          output_data[Offset(output_shape, batch, out_y, out_x, out_channel)] =
              static_cast<int8_t>(acc);
          // printf("=================================\n");
        }
      }
    }
  }
}

// Fixed-point per-channel-quantization convolution reference kernel.
// 16-bit data and 8-bit filter
template <typename AccumScalar>
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int16_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const AccumScalar* bias_data, const RuntimeShape& output_shape,
    int16_t* output_data) {
  // Get parameters.
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;

  // Set min and max value of the output.
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // Consistency check.
  TFLITE_DCHECK_LE(output_activation_min, output_activation_max);
  TFLITE_DCHECK_EQ(input_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(filter_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(output_shape.DimensionsCount(), 4);
  const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int input_depth = input_shape.Dims(3);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  if (bias_data) {
    TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  }

  // Check dimensions of the tensors.
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);
  for (int batch = 0; batch < batches; ++batch) {
    for (int out_y = 0; out_y < output_height; ++out_y) {
      const int in_y_origin = (out_y * stride_height) - pad_height;
      for (int out_x = 0; out_x < output_width; ++out_x) {
        const int in_x_origin = (out_x * stride_width) - pad_width;
        for (int out_channel = 0; out_channel < output_depth; ++out_channel) {
          auto group = out_channel / filters_per_group;
          AccumScalar acc = 0;
          for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
            const int in_y = in_y_origin + dilation_height_factor * filter_y;
            for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
              const int in_x = in_x_origin + dilation_width_factor * filter_x;

              // Zero padding by omitting the areas outside the image.
              const bool is_point_inside_image =
                  (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
                  (in_y < input_height);

              if (!is_point_inside_image) {
                continue;
              }

              for (int in_channel = 0; in_channel < filter_input_depth;
                   ++in_channel) {
                int32_t input_val =
                    input_data[Offset(input_shape, batch, in_y, in_x,
                                      in_channel + group * filter_input_depth)];
                int32_t filter_val = filter_data[Offset(
                    filter_shape, out_channel, filter_y, filter_x, in_channel)];
                // Accumulate with 64 bits accumulator.
                // int64_t += int8_t * int16_t so the highest value we can
                // get from each accumulation is [-127, 127] * ([-32768,
                // 32767] -
                // [-32768, 32767]), which is [-8322945, 8322945].
                // log2(8322945) = 22.99.
                acc += filter_val * input_val;
              }
            }
          }
          if (bias_data) {
            acc += bias_data[out_channel];
          }
          int32_t scaled_acc = MultiplyByQuantizedMultiplier(
              acc, output_multiplier[out_channel], output_shift[out_channel]);
          scaled_acc = std::max(scaled_acc, output_activation_min);
          scaled_acc = std::min(scaled_acc, output_activation_max);
          output_data[Offset(output_shape, batch, out_y, out_x, out_channel)] =
              static_cast<int16_t>(scaled_acc);
        }
      }
    }
  }
}

}  // namespace reference_integer_ops
}  // namespace tflite

#endif  // TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_