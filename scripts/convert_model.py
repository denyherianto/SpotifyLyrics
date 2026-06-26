#!/usr/bin/env python3
"""
Convert the torchaudio MMS forced-alignment model (wav2vec2-based) to Core ML.

Usage:
    pip install torch torchaudio coremltools
    python scripts/convert_model.py

Output:
    Resources/mms_fa.mlpackage/   — Core ML model package
    Resources/mms_fa.mlmodelc/    — Compiled Core ML model (if on macOS)

The model accepts mono 16 kHz Float32 audio and outputs CTC log-probabilities
with shape [1, num_frames, 29] where the vocabulary is:
    0: <blank>
    1-26: a-z
    27: '
    28: | (word separator)
"""

import os
import sys
import argparse
import torch
import torchaudio
import coremltools as ct
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
RESOURCES_DIR = os.path.join(PROJECT_DIR, "Resources")


def main():
    parser = argparse.ArgumentParser(description="Convert MMS FA model to Core ML")
    parser.add_argument("--model", choices=["mms_fa", "wav2vec2_base"], default="mms_fa",
                        help="Model to convert: mms_fa (~1.2GB download, best quality) or "
                             "wav2vec2_base (~360MB download, smaller/faster)")
    args = parser.parse_args()

    os.makedirs(RESOURCES_DIR, exist_ok=True)

    print(f"Loading {args.model} model from torchaudio...")
    if args.model == "mms_fa":
        bundle = torchaudio.pipelines.MMS_FA
    else:
        bundle = torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H

    model = bundle.get_model()
    model.eval()
    sample_rate = bundle.sample_rate  # 16000

    # Print model info
    labels = bundle.get_labels()
    print(f"Sample rate: {sample_rate}")
    print(f"Labels ({len(labels)}): {labels}")
    print(f"Label mapping: {dict(enumerate(labels))}")

    # Create a traced wrapper that takes raw audio and returns log-probs
    class AlignmentModel(torch.nn.Module):
        def __init__(self, wav2vec2_model):
            super().__init__()
            self.model = wav2vec2_model

        def forward(self, waveform):
            # waveform: [1, num_samples]
            emissions, _ = self.model(waveform)
            # emissions: [1, num_frames, num_classes]
            log_probs = torch.log_softmax(emissions, dim=-1)
            return log_probs

    wrapper = AlignmentModel(model)
    wrapper.eval()

    # Trace with example input (5 seconds of audio at 16kHz)
    print("Tracing model...")
    example_input = torch.randn(1, 5 * sample_rate)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example_input)

    # Verify trace output
    with torch.no_grad():
        test_output = traced(example_input)
    print(f"Output shape for 5s input: {test_output.shape}")
    num_classes = test_output.shape[-1]
    print(f"Num classes (vocab size): {num_classes}")

    # Convert to Core ML
    print("Converting to Core ML...")

    # Use flexible input shape: audio can be 0.5s to 30s
    # wav2vec2 produces 1 frame per 20ms, so:
    #   0.5s = 8000 samples -> ~25 frames
    #   30s  = 480000 samples -> ~1500 frames
    input_shape = ct.Shape(
        shape=(1, ct.RangeDim(lower_bound=8000, upper_bound=480000, default=80000))
    )

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=input_shape)],
        outputs=[ct.TensorType(name="log_probs")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS13,
    )

    # Add metadata
    mlmodel.author = "SpotifyLyrics (converted from torchaudio MMS_FA)"
    mlmodel.short_description = (
        "CTC forced alignment model for word-level lyric synchronization. "
        "Input: mono 16kHz audio waveform. "
        "Output: log-probabilities over 29-class CTC vocabulary."
    )
    mlmodel.input_description["audio"] = "Mono 16kHz Float32 audio waveform [1, num_samples]"
    mlmodel.output_description["log_probs"] = (
        "CTC log-probabilities [1, num_frames, 29]. "
        "Vocab: 0=blank, 1-26=a-z, 27=apostrophe, 28=pipe(word-sep)"
    )

    # Save as mlpackage
    mlpackage_path = os.path.join(RESOURCES_DIR, "mms_fa.mlpackage")
    print(f"Saving to {mlpackage_path}...")
    mlmodel.save(mlpackage_path)

    # Compile to mlmodelc on macOS
    try:
        compiled_path = os.path.join(RESOURCES_DIR, "mms_fa.mlmodelc")
        print(f"Compiling to {compiled_path}...")
        compiled = ct.models.CompiledMLModel(mlpackage_path)
        # coremltools compile
        import subprocess
        result = subprocess.run(
            ["xcrun", "coremlcompiler", "compile", mlpackage_path, RESOURCES_DIR],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"Compiled model saved to {compiled_path}")
        else:
            print(f"Compilation warning (model still usable as mlpackage): {result.stderr}")
    except Exception as e:
        print(f"Note: Could not compile model (mlpackage still usable): {e}")

    # Save vocabulary mapping for reference
    vocab_path = os.path.join(RESOURCES_DIR, "mms_fa_vocab.json")
    import json
    vocab = {str(i): label for i, label in enumerate(labels)}
    with open(vocab_path, "w") as f:
        json.dump(vocab, f, indent=2)
    print(f"Vocabulary saved to {vocab_path}")

    # Print size info
    import shutil
    pkg_size = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, dn, filenames in os.walk(mlpackage_path)
        for f in filenames
    )
    print(f"\nModel size: {pkg_size / 1024 / 1024:.1f} MB")
    print("Done!")


if __name__ == "__main__":
    main()
