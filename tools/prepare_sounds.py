#!/usr/bin/env python3
"""Condition sourced sound files into the game's assets/audio convention.

Joshua sources sounds in whatever format/length the library ships (Phase 6.6);
this tool turns them into what the engine expects (assets/audio/README.md):

  slice  — split a recording into individual one-shot takes on its silences
           (a single-step file simply yields one take), each trimmed, faded
           5 ms against clicks, peak-normalized, converted to mono 44.1 kHz
           16-bit wav, and numbered *continuing after* any takes already in
           the destination — so extra variety can be added any time.
  loop   — cut a stretch out of a long ambience recording and make it a
           seamless loop (equal-power crossfade of the tail into the head),
           encoded to stereo .ogg.

Examples:
  python3 tools/prepare_sounds.py slice in.wav assets/audio/footsteps/sand_walk
  python3 tools/prepare_sounds.py slice creak.wav assets/audio/doors/door_open --gap 800 --norm -6
  python3 tools/prepare_sounds.py loop wind.wav assets/audio/ambience/wind_day_loop.ogg --start 20 --length 60

Requires ffmpeg (decode/encode); the DSP itself is dependency-free.
"""

from __future__ import annotations

import argparse
import array
import math
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

RATE = 44100
FADE_MS = 5
PAD_PRE_MS = 15
PAD_POST_MS = 90
MIN_TAKE_MS = 80
WINDOW_MS = 10


def ffmpeg_decode(src: Path, out_wav: Path, channels: int) -> None:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(src),
            "-ac", str(channels), "-ar", str(RATE), "-c:a", "pcm_s16le",
            str(out_wav),
        ],
        check=True,
    )


def read_wav(path: Path) -> tuple[array.array, int]:
    with wave.open(str(path), "rb") as handle:
        assert handle.getsampwidth() == 2, "expected 16-bit PCM"
        channels = handle.getnchannels()
        data = array.array("h")
        data.frombytes(handle.readframes(handle.getnframes()))
    return data, channels


def write_wav(path: Path, samples: array.array, channels: int) -> None:
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(samples.tobytes())


def normalize(samples: list[float], target_db: float) -> list[float]:
    peak = max(1e-9, max(abs(value) for value in samples))
    gain = (10.0 ** (target_db / 20.0)) / peak
    return [value * gain for value in samples]


def to_int16(samples: list[float]) -> array.array:
    return array.array(
        "h", (max(-32768, min(32767, round(value * 32767.0))) for value in samples)
    )


def fade_edges(samples: list[float]) -> None:
    fade = min(int(RATE * FADE_MS / 1000), len(samples) // 2)
    for i in range(fade):
        weight = i / fade
        samples[i] *= weight
        samples[-1 - i] *= weight


def next_take_number(dest_prefix: Path) -> int:
    highest = 0
    pattern = re.compile(re.escape(dest_prefix.name) + r"_(\d{2})\.wav$")
    for existing in dest_prefix.parent.glob(dest_prefix.name + "_*.wav"):
        match = pattern.match(existing.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return highest + 1


def slice_takes(src: Path, dest_prefix: Path, gap_ms: int, norm_db: float) -> None:
    with tempfile.TemporaryDirectory() as scratch:
        mono = Path(scratch) / "mono.wav"
        ffmpeg_decode(src, mono, channels=1)
        data, _ = read_wav(mono)

    window = RATE * WINDOW_MS // 1000
    rms: list[float] = []
    for start in range(0, len(data) - window, window):
        total = 0
        for i in range(start, start + window):
            total += data[i] * data[i]
        rms.append(math.sqrt(total / window) / 32768.0)
    peak = max(rms)
    on_level = peak * 0.06
    off_level = peak * 0.04
    gap_windows = max(1, gap_ms // WINDOW_MS)

    takes: list[tuple[int, int]] = []
    index = 0
    while index < len(rms):
        if rms[index] < on_level:
            index += 1
            continue
        end = index
        quiet = 0
        while end < len(rms) and quiet < gap_windows:
            quiet = quiet + 1 if rms[end] < off_level else 0
            end += 1
        takes.append((index * window, end * window))
        index = end

    pad_pre = RATE * PAD_PRE_MS // 1000
    pad_post = RATE * PAD_POST_MS // 1000
    written = 0
    number = next_take_number(dest_prefix)
    dest_prefix.parent.mkdir(parents=True, exist_ok=True)
    for take_start, take_end in takes:
        lo = max(0, take_start - pad_pre)
        hi = min(len(data), take_end + pad_post)
        if (hi - lo) < RATE * MIN_TAKE_MS // 1000:
            continue
        samples = [value / 32768.0 for value in data[lo:hi]]
        samples = normalize(samples, norm_db)
        fade_edges(samples)
        out = dest_prefix.parent / f"{dest_prefix.name}_{number:02d}.wav"
        write_wav(out, to_int16(samples), channels=1)
        print(f"  {out.name}  ({(hi - lo) / RATE:.2f} s)")
        number += 1
        written += 1
    print(f"slice: {written} take(s) from {src.name}")


def build_loop(
    src: Path, dest: Path, start_s: float, length_s: float, xfade_s: float, norm_db: float
) -> None:
    with tempfile.TemporaryDirectory() as scratch:
        stereo = Path(scratch) / "stereo.wav"
        ffmpeg_decode(src, stereo, channels=2)
        data, channels = read_wav(stereo)

        frames = len(data) // channels
        begin = int(start_s * RATE)
        body = int(length_s * RATE)
        fade = int(xfade_s * RATE)
        assert begin + body + fade <= frames, "source too short for start+length+xfade"

        samples = [value / 32768.0 for value in data]

        def frame(at: int, channel: int) -> float:
            return samples[(begin + at) * channels + channel]

        out: list[float] = []
        for i in range(body):
            for channel in range(channels):
                value = frame(i, channel)
                if i < fade:
                    # Equal-power blend of the tail (past the loop end) into
                    # the head, so the seam at wrap-around is inaudible.
                    mix = i / fade
                    value = frame(i, channel) * math.sin(mix * math.pi / 2.0) + frame(
                        body + i, channel
                    ) * math.cos(mix * math.pi / 2.0)
                out.append(value)

        out = normalize(out, norm_db)
        loop_wav = Path(scratch) / "loop.wav"
        write_wav(loop_wav, to_int16(out), channels)
        dest.parent.mkdir(parents=True, exist_ok=True)
        # oggenc, not ffmpeg: the Homebrew ffmpeg ships without libvorbis and
        # its built-in vorbis encoder audibly warbles on noise-like ambience.
        subprocess.run(
            ["oggenc", "--quiet", "-q", "5", "-o", str(dest), str(loop_wav)],
            check=True,
        )
    print(f"loop: {dest.name}  ({length_s:.0f} s seamless)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    slicer = commands.add_parser("slice", help="split a recording into one-shot takes")
    slicer.add_argument("src", type=Path)
    slicer.add_argument("dest_prefix", type=Path, help="e.g. assets/audio/footsteps/sand_walk")
    slicer.add_argument("--gap", type=int, default=140, help="silence that ends a take, ms")
    slicer.add_argument("--norm", type=float, default=-4.0, help="peak target, dBFS")

    looper = commands.add_parser("loop", help="make a seamless ambience loop")
    looper.add_argument("src", type=Path)
    looper.add_argument("dest", type=Path, help="e.g. assets/audio/ambience/wind_day_loop.ogg")
    looper.add_argument("--start", type=float, default=10.0, help="segment start, s")
    looper.add_argument("--length", type=float, default=60.0, help="loop length, s")
    looper.add_argument("--xfade", type=float, default=3.0, help="seam crossfade, s")
    looper.add_argument("--norm", type=float, default=-6.0, help="peak target, dBFS")

    options = parser.parse_args()
    if options.command == "slice":
        slice_takes(options.src, options.dest_prefix, options.gap, options.norm)
    else:
        build_loop(
            options.src, options.dest, options.start, options.length, options.xfade,
            options.norm,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
