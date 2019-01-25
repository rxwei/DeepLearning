
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if !COMPILING_TENSORFLOW_MODULE
import TensorFlow
#endif

// `pow` is defined in Darwin/Glibc on `Float` and `Double`, but there doesn't exist a generic
// version for `FloatingPoint`.
// This is a manual definition.
func pow<T : BinaryFloatingPoint>(_ x: T, _ y: T) -> T {
    return T(pow(Double(x), Double(y)))
}
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if !COMPILING_TENSORFLOW_MODULE
@_exported import TensorFlow
#endif

public extension Tensor where Scalar : BinaryFloatingPoint,
                              Scalar.RawSignificand : FixedWidthInteger {
   /// Performs Glorot uniform initialization for the specified shape,
   /// creating a tensor by randomly sampling scalar values from a uniform
   /// distribution between -limit and limit, where limit is
   /// sqrt(6 / (fanIn + fanOut)), using the default RNG
   ///
   /// - Parameters:
   ///   - shape: The dimensions of the tensor.
   ///
    init(glorotUniform shape: TensorShape) {
        let fanIn = shape[shape.count - 2]
        let fanOut = shape[shape.count - 1]
        let minusOneToOne = 2 * Tensor(randomUniform: shape) - 1
        self = sqrt(Scalar(6) / Scalar(fanIn + fanOut)) * minusOneToOne
    }
}
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if !COMPILING_TENSORFLOW_MODULE
@_exported import TensorFlow
#endif

/// A neural network layer.
///
/// Types that conform to `Layer` represent functions that map inputs to
/// outputs. They may have an internal state represented by parameters, such as
/// weight tensors.
///
/// `Layer` instances define a differentiable `applied(to:)` method for mapping
/// inputs to outputs.
public protocol Layer: Differentiable & KeyPathIterable
    where AllDifferentiableVariables: KeyPathIterable {
    /// The input type of the layer.
    associatedtype Input: Differentiable
    /// The output type of the layer.
    associatedtype Output: Differentiable

    /// Returns the output obtained from applying to an input.
    @differentiable(wrt: (self, input))
    func applied(to input: Input) -> Output
}

public extension Layer {
    func valueWithPullback(at input: Input)
        -> (output: Output,
            pullback: (Output.CotangentVector)
                -> (layerGradient: CotangentVector, inputGradient: Input.CotangentVector)) {
        let (out, pullback) = _valueWithPullback(at: self, input, in: Self.applied(to:))
        return (out, pullback)
    }
}

/// A mutable, shareable flag that denotes training vs. inference
///
/// In typical uses, every layer in a model that has behavior which differs
/// between training and inference shares an instance of ModeRef so it doesn't
/// need to be toggled or threaded through in more than one place.
public class ModeRef {
    var training: Bool = true
}

/// A mutable, shareable reference to a tensor
public class Parameter<T : TensorFlowScalar> {
    var value: Tensor<T>
    public init(_ value: Tensor<T>) {
        self.value = value
    }
}

@_fixed_layout
public struct Dense<Scalar>: Layer
    where Scalar: FloatingPoint & Differentiable & TensorFlowScalar {

    public var weight: Tensor<Scalar>
    public var bias: Tensor<Scalar>

    // FIXME(SR-9716): Remove this once the bug is fixed or worked around.
    public var allKeyPaths: [PartialKeyPath<Dense>] {
        return [\Dense.weight, \Dense.bias]
    }

    @differentiable(wrt: (self, input))
    public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        return matmul(input, weight) + bias
    }
}

public extension Dense where Scalar : BinaryFloatingPoint,
                             Scalar.RawSignificand : FixedWidthInteger {
    // init(inputSize: Int, outputSize: Int, activation: @escaping Activation = { $0 }) {
    init(inputSize: Int, outputSize: Int) {
        self.init(weight: Tensor(
                  glorotUniform: [Int32(inputSize), Int32(outputSize)]),
                  bias: Tensor(zeros: [Int32(outputSize)]))
    }
}

@_fixed_layout
public struct Conv2D<Scalar>: Layer
    where Scalar: FloatingPoint & Differentiable & TensorFlowScalar {
    public var filter: Tensor<Scalar>
    @noDerivative public let strides: (Int32, Int32)
    @noDerivative public let padding: Padding

    @differentiable(wrt: (self, input))
    public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        return input.convolved2D(withFilter: filter,
                                 strides: (1, strides.0, strides.1, 1),
                                 padding: padding)
    }
}

public extension Conv2D where Scalar : BinaryFloatingPoint,
                              Scalar.RawSignificand : FixedWidthInteger {
    init(
        filterShape: (Int, Int, Int, Int),
        strides: (Int, Int) = (1, 1),
        padding: Padding
    ) {
        let filterTensorShape = TensorShape([
            Int32(filterShape.0), Int32(filterShape.1),
            Int32(filterShape.2), Int32(filterShape.3)])
        self.init(
            filter: Tensor(glorotUniform: filterTensorShape),
            strides: (Int32(strides.0), Int32(strides.1)), padding: padding)
    }
}

@_fixed_layout
public struct BatchNorm<Scalar>: Layer
    where Scalar: BinaryFloatingPoint & Differentiable & TensorFlowScalar {
    /// The batch dimension.
    @noDerivative public let axis: Int32

    /// The momentum for the running mean and running variance.
    @noDerivative public let momentum: Tensor<Scalar>

    /// The offset value, also known as beta.
    public var offset: Tensor<Scalar>

    /// The scale value, also known as gamma.
    public var scale: Tensor<Scalar>

    /// The variance epsilon value.
    @noDerivative public let epsilon: Tensor<Scalar>

    /// The running mean.
    @noDerivative public let runningMean: Parameter<Scalar>

    /// The running variance.
    @noDerivative public let runningVariance: Parameter<Scalar>

    @noDerivative public let mode: ModeRef

    @differentiable(wrt: (self, input))
    private func applyTraining(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        let mean = input.mean(alongAxes: axis)
        let variance = input.variance(alongAxes: axis)
        runningMean.value += (mean - runningMean.value) * (1 - momentum)
        runningVariance.value += (
            variance - runningVariance.value) * (1 - momentum)
        let inv = rsqrt(variance + epsilon) * scale
        return (input - mean) * inv + offset
    }

    @differentiable(wrt: (self, input))
    private func applyInference(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        let inv = rsqrt(runningVariance.value + epsilon) * scale
        return (input - runningMean.value) * inv + offset
    }

    // TODO fix crasher in the below to enable behavior that differs between
    // training and inference
    //
    // @differentiable(wrt: (self, input), vjp: _vjpApplied(to:))
    // public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
    //     if mode.training {
    //         return applyTraining(to: input)
    //     } else {
    //         return applyInference(to: input)
    //     }
    // }
    //
    // public func _vjpApplied(to input: Tensor<Scalar>) ->
    //     (Tensor<Scalar>, (Tensor<Scalar>) ->
    //         (BatchNorm<Scalar>.CotangentVector, Tensor<Scalar>)) {
    //     if mode.training {
    //         return Swift.valueWithPullback(at: self, input) {
    //             $0.applyTraining(to: $1)
    //         }
    //     } else {
    //         return Swift.valueWithPullback(at: self, input) {
    //             $0.applyInference(to: $1)
    //         }
    //     }
    // }
    //
    // Work around for now by always using training mode
    @differentiable(wrt: (self, input))
    public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        return applyTraining(to: input)
    }

    public init(featureCount: Int,
                modeRef: ModeRef,
                axis: Int = 0,
                momentum: Tensor<Scalar> = Tensor(0.99),
                epsilon: Tensor<Scalar> = Tensor(0.001)) {
        self.axis = Int32(axis)
        self.momentum = momentum
        self.scale = Tensor<Scalar>(ones: [Int32(featureCount)])
        self.offset = Tensor<Scalar>(zeros: [Int32(featureCount)])
        self.epsilon = epsilon
        self.runningMean = Parameter(Tensor(0))
        self.runningVariance = Parameter(Tensor(1))
        self.mode = modeRef
    }
}

@_fixed_layout
public struct MaxPool2D<Scalar>: Layer
    where Scalar : BinaryFloatingPoint & Differentiable & TensorFlowScalar {
    /// The size of the sliding reduction window for pooling.
    @noDerivative let poolSize: (Int32, Int32, Int32, Int32)

    /// The strides of the sliding window for each dimension of a 4-D input.
    /// Strides in non-spatial dimensions must be 1.
    @noDerivative let strides: (Int32, Int32, Int32, Int32)

    /// The padding algorithm for pooling.
    @noDerivative let padding: Padding

    // strides are just for the spatial dimensions (H and W)
    public init(poolSize: (Int, Int), strides: (Int, Int), padding: Padding) {
        self.poolSize = (1, Int32(poolSize.0), Int32(poolSize.1), 1)
        self.strides = (1, Int32(strides.0), Int32(strides.1), 1)
        self.padding = padding
    }

    @differentiable(wrt: (self, input))
    public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        return input.maxPooled(
          kernelSize: poolSize, strides: strides, padding: padding)
    }
}

@_fixed_layout
public struct AvgPool2D<Scalar>: Layer
    where Scalar : BinaryFloatingPoint & Differentiable & TensorFlowScalar {
    /// The size of the sliding reduction window for pooling.
    @noDerivative let poolSize: (Int32, Int32, Int32, Int32)

    /// The strides of the sliding window for each dimension of a 4-D input.
    /// Strides in non-spatial dimensions must be 1.
    @noDerivative let strides: (Int32, Int32, Int32, Int32)

    /// The padding algorithm for pooling.
    @noDerivative let padding: Padding

    // strides are just for the spatial dimensions (H and W)
    public init(poolSize: (Int, Int), strides: (Int, Int), padding: Padding) {
        self.poolSize = (1, Int32(poolSize.0), Int32(poolSize.1), 1)
        self.strides = (1, Int32(strides.0), Int32(strides.1), 1)
        self.padding = padding
    }

    @differentiable(wrt: (self, input))
    public func applied(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        return input.averagePooled(
          kernelSize: poolSize, strides: strides, padding: padding)
    }
}
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if !COMPILING_TENSORFLOW_MODULE
import TensorFlow
#endif

@differentiable
public func meanSquaredError<Scalar: Differentiable & FloatingPoint>(
    predicted: Tensor<Scalar>, expected: Tensor<Scalar>) -> Tensor<Scalar> {
    return (expected - predicted).squared().mean()
}

public func softmaxCrossEntropy<Scalar: FloatingPoint>(
    logits: Tensor<Scalar>, labels: Tensor<Scalar>) -> Tensor<Scalar> {
    return -(labels * logSoftmax(logits)).sum()
}
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if !COMPILING_TENSORFLOW_MODULE
import TensorFlow
#endif

public protocol Optimizer {
    associatedtype Model: Layer
    associatedtype Scalar: FloatingPoint
    var learningRate: Scalar { get }
    mutating func update(_ variables: inout Model.AllDifferentiableVariables,
                         along gradient: Model.CotangentVector)
}

// MARK: - Key-path based optimizers

public class Adam<Model: Layer, Scalar: BinaryFloatingPoint & TensorFlowScalar>: Optimizer
    where Model.AllDifferentiableVariables: AdditiveArithmetic,
          Model.AllDifferentiableVariables == Model.CotangentVector {
    public let learningRate: Scalar
    public var beta1: Scalar
    public var beta2: Scalar
    public let epsilon: Scalar
    public let decay: Scalar

    public init(
        learningRate: Scalar = 1e-3,
        beta1: Scalar = 0.9,
        beta2: Scalar = 0.999,
        epsilon: Scalar = 1e-8,
        decay: Scalar = 0
    ) {
        precondition(learningRate >= 0, "Learning rate must be non-negative")
        precondition(0 <= beta1 && beta1 <= 1, "Beta parameter must be between 0 and 1")
        precondition(0 <= beta2 && beta2 <= 1, "Beta parameter must be between 0 and 1")
        precondition(decay >= 0, "Weight decay must be non-negative")

        self.learningRate = learningRate
        self.beta1 = beta1
        self.beta2 = beta2
        self.epsilon = epsilon
        self.decay = decay
    }

    private var step: Scalar = 0
    private var firstMoments = Model.AllDifferentiableVariables.zero
    private var secondMoments = Model.AllDifferentiableVariables.zero

    public func update(_ model: inout Model.AllDifferentiableVariables,
                       along gradient: Model.AllDifferentiableVariables) {
        step += 1
        let learningRate = self.learningRate * 1 / (1 + decay * step)
        let stepSize = learningRate * (sqrt(1 - pow(beta2, step)) / (1 - pow(beta1, step)))
        for kp in model.recursivelyAllWritableKeyPaths(to: Tensor<Scalar>.self) {
            firstMoments[keyPath: kp] =
                firstMoments[keyPath: kp] * beta1 + (1 - beta1) * gradient[keyPath: kp]
            secondMoments[keyPath: kp] =
                secondMoments[keyPath: kp] * beta2 + (1 - beta2) *
                     gradient[keyPath: kp] * gradient[keyPath: kp]
            model[keyPath: kp] -=
                stepSize * firstMoments[keyPath: kp] / (sqrt(secondMoments[keyPath: kp]) + epsilon)
        }
    }
}

public class RMSProp<Model: Layer, Scalar: BinaryFloatingPoint & TensorFlowScalar>: Optimizer
    where Model.AllDifferentiableVariables: AdditiveArithmetic,
          Model.AllDifferentiableVariables == Model.CotangentVector {
    public let learningRate: Scalar
    public let rho: Scalar
    public let epsilon: Scalar
    public let decay: Scalar

    public init(
        learningRate: Scalar = 0.001,
        rho: Scalar = 0.9,
        epsilon: Scalar = 1e-8,
        decay: Scalar = 0
    ) {
        precondition(learningRate >= 0, "Learning rate must be non-negative")
        precondition(rho >= 0, "Rho must be non-negative")
        precondition(decay >= 0, "Weight decay must be non-negative")

        self.learningRate = learningRate
        self.rho = rho
        self.epsilon = epsilon
        self.decay = decay
    }

    private var step: Scalar = 0
    private var alpha = Model.AllDifferentiableVariables.zero

    public func update(_ model: inout Model.AllDifferentiableVariables,
                       along gradient: Model.CotangentVector) {
        step += 1
        let learningRate = self.learningRate * 1 / (1 + decay * step)
        for kp in model.recursivelyAllWritableKeyPaths(to: Tensor<Scalar>.self) {
            alpha[keyPath: kp] =
                rho * alpha[keyPath: kp] + (1 - rho) * pow(gradient[keyPath: kp], 2)
            model[keyPath: kp] -=
                learningRate * gradient[keyPath: kp] / (sqrt(alpha[keyPath: kp]) + epsilon)
        }
    }
}

public class SGD<Model: Layer, Scalar: BinaryFloatingPoint & TensorFlowScalar>: Optimizer
    where Model.AllDifferentiableVariables: AdditiveArithmetic,
          Model.AllDifferentiableVariables == Model.CotangentVector {
    public let learningRate: Scalar
    public let momentum: Scalar
    public let decay: Scalar
    public let nesterov: Bool

    public init(
        learningRate: Scalar = 0.01,
        momentum: Scalar = 0,
        decay: Scalar = 0,
        nesterov: Bool = false
    ) {
        precondition(learningRate >= 0, "Learning rate must be non-negative")
        precondition(momentum >= 0, "Momentum must be non-negative")
        precondition(decay >= 0, "Weight decay must be non-negative")

        self.learningRate = learningRate
        self.momentum = momentum
        self.decay = decay
        self.nesterov = nesterov
    }

    private var step: Scalar = 0
    private var velocity = Model.AllDifferentiableVariables.zero

    public func update(_ model: inout Model.AllDifferentiableVariables,
                       along gradients: Model.CotangentVector) {
        step += 1
        let learningRate = self.learningRate * 1 / (1 + decay * step)
        for kp in model.recursivelyAllWritableKeyPaths(to: Tensor<Scalar>.self) {
            velocity[keyPath: kp] =
                momentum * velocity[keyPath: kp] - learningRate * gradients[keyPath: kp]
            if nesterov {
                model[keyPath: kp] +=
                    momentum * velocity[keyPath: kp] - learningRate * gradients[keyPath: kp]
            } else {
                model[keyPath: kp] += velocity[keyPath: kp]
            }
        }
    }
}

// MARK: - Manifold optimizers

public class RiemannSGD<Model: Layer, Scalar: FloatingPoint>: Optimizer
    where Model.TangentVector: VectorNumeric, Model.TangentVector.Scalar == Scalar {
    public var learningRate: Scalar

    public init(learningRate: Scalar) {
        self.learningRate = learningRate
    }

    public func update(_ model: inout Model.AllDifferentiableVariables,
                       along gradient: Model.CotangentVector) {
        model = model.moved(along: learningRate * (.zero - model.tangentVector(from: gradient)))
    }
}
// Copyright 2018 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


import Python

infix operator .== : ComparisonPrecedence

let gzip = Python.import("gzip")
let np = Python.import("numpy")

func readImagesFile(_ filename: String) -> [Float] {
    let file = gzip.open(filename, "rb").read()
    let data = np.frombuffer(file, dtype: np.uint8, offset: 16)
    let array = data.astype(np.float32) / 255
    return Array(numpyArray: array)!
}

func readLabelsFile(_ filename: String) -> [Int32] {
    let file = gzip.open(filename, "rb").read()
    let data = np.frombuffer(file, dtype: np.uint8, offset: 8)
    let array = data.astype(np.int32)
    return Array(numpyArray: array)!
}

/// Reads MNIST images and labels from specified file paths.
func readMNIST(imagesFile: String, labelsFile: String)
    -> (images: Tensor<Float>, labels: Tensor<Int32>) {
    print("Reading data.")
    let images = readImagesFile(imagesFile)
    let labels = readLabelsFile(labelsFile)
    let rowCount = Int32(labels.count)
    let columnCount = Int32(images.count) / rowCount

    print("Constructing data tensors.")
    let imagesTensor = Tensor(shape: [rowCount, columnCount], scalars: images) / 255
    let labelsTensor = Tensor(labels)
    return (imagesTensor, labelsTensor)
}

struct MNISTClassifier: Layer {
    var l1, l2: Dense<Float>
    init(hiddenSize: Int) {
        l1 = Dense<Float>(inputSize: 784, outputSize: hiddenSize)
        l2 = Dense<Float>(inputSize: hiddenSize, outputSize: 10)
    }
    func applied(to input: Tensor<Float>) -> Tensor<Float> {
        let h1 = sigmoid(l1.applied(to: input))
        return logSoftmax(l2.applied(to: h1))
    }
}

func testMNIST() {
    // Get training data.
    let (images, numericLabels) = readMNIST(imagesFile: "train-images-idx3-ubyte.gz",
                                            labelsFile: "train-labels-idx1-ubyte.gz")
    let labels = Tensor<Float>(oneHotAtIndices: numericLabels, depth: 10)

    let batchSize = images.shape[0]
    let optimizer = RMSProp<MNISTClassifier, Float>(learningRate: 0.2)
    var classifier = MNISTClassifier(hiddenSize: 30)

    // Hyper-parameters.
    let epochCount = 20
    let minibatchSize: Int32 = 10
    let learningRate: Float = 0.2
    var loss = Float.infinity

    // Training loop.
    print("Begin training for \(epochCount) epochs.")

    func minibatch<Scalar>(_ x: Tensor<Scalar>, index: Int32) -> Tensor<Scalar> {
        let start = index * minibatchSize
        return x[start..<start+minibatchSize]
    }

    for epoch in 0...epochCount {
        // Store information for printing accuracy and loss.
        var correctPredictions = 0
        var totalLoss: Float = 0

        let iterationCount = batchSize / minibatchSize
        for i in 0..<iterationCount {
            let images = minibatch(images, index: i)
            let numericLabels = minibatch(numericLabels, index: i)
            let labels = minibatch(labels, index: i)

            let (loss, 𝛁model) = classifier.valueWithGradient { classifier -> Tensor<Float> in
                let ŷ = classifier.applied(to: images)

                // Update number of correct predictions.
                let correctlyPredicted = ŷ.argmax(squeezingAxis: 1) .== numericLabels
                correctPredictions += Int(Tensor<Int32>(correctlyPredicted).sum().scalarized())

                return -(labels * ŷ).sum() / Tensor(10)
            }
            optimizer.update(&classifier.allDifferentiableVariables, along: 𝛁model)
            totalLoss += loss.scalarized()
        }
        print("""
            [Epoch \(epoch)] \
            Accuracy: \(correctPredictions)/\(batchSize) \
            (\(Float(correctPredictions) / Float(batchSize)))\t\
            Loss: \(totalLoss / Float(batchSize))
            """)
    }
    print("Done training MNIST.")
}
testMNIST()