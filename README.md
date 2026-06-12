# sc-conductor-io

Metronome-synchronized **live IO** framework for SuperCollider — a click-track conductor drives modular **input** and **output** routines within preset-defined bar/beat windows.

**Composer / developer:** Aykut Çağlayan

## Overview

During live performance, a metronome broadcasts OSC timing (`/metronome`, `/metronome/reset`). Input routines capture and analyze audio in configured windows; output routines trigger sonification and playback at bar/beat points. A preset file encodes the full performance timeline.

```
metronome.scd  ──OSC──►  routines.scd  ──►  inputs/  ──►  bufferDict  ──►  outputs/  ──►  main out
```

| File | Role |
|------|------|
| [`metronome.scd`](metronome.scd) | Click-track conductor with GUI; sends `[bar, beat, bpm]` on `/metronome` |
| [`routines.scd`](routines.scd) | Main controller — loads preset, SynthDefs, input/output routines |
| [`routines_gui.scd`](routines_gui.scd) | Optional preset editor and process overview |
| [`presets/`](presets/) | Performance timeline files (`.preset`) |

## Quick start

### Requirements

- [SuperCollider](https://supercollider.github.io/) 3.12+
- [Flucoma](https://www.flucoma.org/) plugins (for MIR routines)
- Audio interface with microphone on input bus 0

### Demo

1. Boot the SuperCollider server.
2. Open and run [`metronome.scd`](metronome.scd) — click **Start**.
3. Open and run [`routines.scd`](routines.scd) — default preset is `presets/grant_demo.preset`.
4. Play or route audio to input bus 0 during bars 2–4; listen for peak sonification at bar 5.
5. Optional: run [`routines_gui.scd`](routines_gui.scd) to inspect the preset.

Press **Reset** in the metronome GUI to re-arm routines without reloading.

For a zero-dependency smoke test (no microphone), set `presetPath` in `routines.scd` to `presets/example.preset`.

## Available routine types

### Inputs

| Type | File | SynthDef | Description |
|------|------|----------|-------------|
| `\bufferRecord` | `buffer_record_input.scd` | `buffer_recorder_synth.scd` | Records audio to a buffer for later playback |
| `\pitchTracker` | `pitch_tracker.scd` | `pitch_tracker_synth.scd` | Tracks pitch and stores trajectory data |
| `\violinRes` | `violin_res.scd` | `violin_res_synth.scd` | Resonant filter excited by audio input |
| `\simpleSine` | `simple_sine.scd` | *(inline)* | Simple sine tone input |
| `\livePitches` | `live_pitches.scd` | `live_pitches_analyzer.scd` | Real-time pitch tracking + sine sonification via FluidPitch |
| `\sineFeature` | `sine_feature.scd` | `sine_feature_analyzer.scd` | Extracts spectral peaks via FluidSineFeature |
| `\storePitches` | `store_pitches.scd` | `store_pitches_analyzer.scd` | Accumulates pitch trajectory via FluidPitch |

### Outputs

| Type | File | SynthDef | Required Source | Description |
|------|------|----------|-----------------|-------------|
| `\bufferPlayOutput` | `buffer_play_output.scd` | `buffer_player_synth.scd` | `\bufferRecord` | Plays a recorded buffer |
| `\simpleSynthOut` | `simple_synth_out.scd` | *(inline)* | — | Simple synth output |
| `\bufferSequence` | `buffer_sequence.scd` | `buffer_sequencer.scd` | `\bufferRecord` | Buffer player with optional LFO rate modulation |
| `\onsetSlice` | `onset_slice.scd` | `onset_slicer.scd` | Buffer with onset indices | Plays one onset slice of a buffer |
| `\peakSonify` | `peak_sonify.scd` | `peak_sonifier.scd` | `\sineFeature` | Sustained sines at captured spectral peaks |
| `\pitchSonify` | `pitch_sonify.scd` | `pitch_sonifier.scd` | `\storePitches` | Plays stored pitch trajectory as sine tones |
| `\pitchShift` | `pitch_shift.scd` | `pitch_shift_synth.scd` | — | Live audio pitch shifting |

### Suggested pairings

| Input | Output | Data in bufferDict |
|-------|--------|--------------------|
| `\sineFeature` | `\peakSonify` | `(freqs, mags, numPeaks)` |
| `\storePitches` | `\pitchSonify` | `(pitches, confidences)` |
| `\bufferRecord` | `\bufferPlayOutput` or `\bufferSequence` | `Buffer` |

## Multi-stage FX chaining

FX chains route one output routine's audio through processing stages before the main out. Configure in the preset under `fxChains`. See the original design notes in this README's history or inspect `routines.scd` and preset examples.

Preset buffer paths may be relative to the repo root (e.g. `samples/Celesta_F.wav`); see [`samples/README.md`](samples/README.md).

## Related repositories

| Repository | Focus |
|------------|-------|
| **[Celesta_piece](https://github.com/ayk-caglayan/Celesta_piece)** *(when published)* | Celesta composition + grant presentation assets |
| **[chord_study](https://github.com/ayk-caglayan/chord_study)** *(when published)* | Symmetric PC-set harmonic research |

This framework was developed for a celesta composition with live electronics. The composition repo includes score excerpts and reference samples; this repo contains the full extensible performance system.

## License

SuperCollider code: MIT License — see [LICENSE](LICENSE).

The violin waveguide SynthDef derives from a Faust physical model (MIT — Romain Michon, GRAME).
