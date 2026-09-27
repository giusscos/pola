#!/bin/sh
# Xcode Cloud: since Xcode 26 the Metal compiler is a separate download, and fresh
# build machines don't have it. PolaroidKernels.metal needs it to compile.
set -e
xcodebuild -downloadComponent MetalToolchain
