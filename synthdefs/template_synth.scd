// Template SynthDef
// Copy and modify for new synth definitions
//
// NAMING CONVENTION:
// - File: descriptive_name_synth.scd
// - SynthDef name: \descriptiveNameSynth
//
// USAGE:
// - Referenced in routine @meta block: requiredSynthdefs: ["your_synth.scd"]
// - Called from routine: Synth(\yourSynthName, [...], server)
//
// @meta: (
//   name: \templateSynth,
//   displayName: "Template Synth",
//   parameters: [
//     (name: \amp,     default: 0.5,  min: 0.0,  max: 1.0, type: \float, label: "Amplitude"),
//     (name: \pan,     default: 0.0,  min: -1.0, max: 1.0, type: \float, label: "Pan"),
//     (name: \attack,  default: 0.01, min: 0.001,max: 5.0, type: \float, label: "Attack (s)"),
//     (name: \release, default: 0.1,  min: 0.001,max: 5.0, type: \float, label: "Release (s)")
//   ]
// )

SynthDef(\templateSynth, {
	arg amp = 0.5,        // Amplitude (0-1)
	    pan = 0,          // Stereo pan (-1 to 1)
	    gate = 1,         // Gate for envelope (1 = on, 0 = release)
	    attack = 0.01,    // Attack time (seconds)
	    release = 0.1;    // Release time (seconds)

	var sig, env;

	// Envelope (ASR with gate control)
	env = EnvGen.kr(
		Env.asr(attack, 1, release),
		gate,
		doneAction: 2     // Free synth when envelope ends
	);

	// Signal generation (replace with your implementation)
	sig = SinOsc.ar(440) * env * amp;

	// Stereo output with panning
	sig = Pan2.ar(sig, pan);
	Out.ar(0, sig);
}).add;

/*
=============================================================================
IMPLEMENTATION CHECKLIST
=============================================================================

1. Copy this file and rename:
   template_synth.scd -> your_synth_name_synth.scd

2. Rename the SynthDef:
   \templateSynth -> \yourSynthNameSynth

3. Add your arguments:
   - For inputs: inBus, bufNum, etc.
   - For outputs: bufNum, bufRate, startPos, durSec, etc.

4. Implement signal processing:
   - Replace placeholder SinOsc with your logic
   - Use appropriate UGens for your purpose

5. Choose doneAction strategy:
   - doneAction: 2 on envelope -> synth frees when envelope ends
   - doneAction: 2 on PlayBuf/RecordBuf -> synth frees when buffer ends
   - doneAction: 0 -> synth must be freed manually by routine

6. Reference in routine @meta:
   requiredSynthdefs: ["your_synth_name_synth.scd"]

=============================================================================
COMMON PATTERNS
=============================================================================

// BUFFER RECORDING (input synths):
sig = In.ar(inBus, 1) * amp;
RecordBuf.ar(sig, bufNum, loop: 0, doneAction: 2);

// BUFFER PLAYBACK (output synths):
sig = PlayBuf.ar(1, bufNum, bufRate * BufRateScale.ir(bufNum),
    1, startPos * BufFrames.ir(bufNum), loop, doneAction: 0);

// FIXED DURATION ENVELOPE:
env = EnvGen.kr(Env.linen(attack, sustain, release), doneAction: 2);

// GATE-CONTROLLED ENVELOPE:
env = EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);

// STEREO OUTPUT:
sig = Pan2.ar(sig, pan);
Out.ar(0, sig);

=============================================================================
*/
