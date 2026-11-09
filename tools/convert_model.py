"""Converts OpenCV's SFace face recognition model (Apache 2.0) to Core ML and checks the result against the original.

Usage: python convert_model.py <input.onnx> <output.mlpackage>
"""

import sys

import coremltools as ct
import numpy as np
import onnx
import onnxruntime
import torch
from onnx2torch import convert
from PIL import Image


def main(onnx_path, output_path):
    network = convert(onnx.load(onnx_path)).eval()
    with torch.no_grad():
        traced = torch.jit.trace(network, torch.rand(1, 3, 112, 112))

    model = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, 112, 112), color_layout=ct.colorlayout.RGB, scale=1.0)],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT32,
    )
    model.short_description = "SFace face recognition, converted from OpenCV's model zoo. Apache 2.0."
    model.save(output_path)

    session = onnxruntime.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    worst = 1.0
    for seed in range(5):
        pixels = np.random.default_rng(seed).integers(0, 256, (112, 112, 3), dtype=np.uint8)
        tensor = pixels.astype(np.float32).transpose(2, 0, 1)[None]
        expected = session.run(None, {input_name: tensor})[0].ravel()
        actual = model.predict({"image": Image.fromarray(pixels, "RGB")})["embedding"].ravel()
        similarity = float(np.dot(expected, actual) / (np.linalg.norm(expected) * np.linalg.norm(actual)))
        worst = min(worst, similarity)

    print(f"embedding size {expected.size}, lowest agreement with original {worst:.6f}")
    if worst < 0.999:
        sys.exit("Converted model doesn't match the original.")
    print("CONVERSION_OK")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
