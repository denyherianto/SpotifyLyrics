#!/bin/bash
set -e
echo "Building SpotifyLyrics..."
swift build -c release --product SpotifyLyrics 2>&1
echo "Running SpotifyLyrics..."
.build/release/SpotifyLyrics
