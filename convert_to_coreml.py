#!/usr/bin/env python3
"""
Convert Silero VAD ONNX model to CoreML format
"""

try:
    import coremltools as ct
    import onnx
except ImportError:
    print("Please install required packages:")
    print("pip install coremltools onnx onnxruntime")
    exit(1)

# Load and convert the model
print("Loading ONNX model...")

print("Converting to CoreML...")
# Silero VAD expects chunks of audio data
# Input: audio chunk of 512 samples at 16kHz (32ms)
coreml_model = ct.convert(
    model="silero_vad.onnx",
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS15,
    inputs=[
        ct.TensorType(name="input", shape=(1, 512))  # 512 samples at 16kHz = 32ms
    ]
)

print("Saving CoreML model...")
coreml_model.save("/Users/ebowwa/apps/ios/VAD-Test/VAD-Test/Models/silero_vad.mlpackage")
print("Conversion complete!")