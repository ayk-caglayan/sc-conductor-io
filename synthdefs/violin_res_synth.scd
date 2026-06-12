// Violin Resonator SynthDef
// Live audio input shaped by a violin waveguide model.
// The string, bridge, nut filters, and body resonance act as a resonant
// filter on the incoming sound.  All physical-model internals are exposed
// as arguments so they can be driven from presets.
//
// Derived from sc/faust/violin_res_synth.scd with every hardcoded constant
// promoted to a controllable arg.
//
// Usage (standalone - hardware input):
//   v = Synth(\violinResSynth, [\inBus, 0, \length, 0.75]);
//   v.set(\bodyFreq, 800, \bridgeReflCoeff, 0.4);
//   v.set(\gate, 0);
//
// Usage (FX chain - reading from a private bus):
//   v = Synth(\violinResSynth, [\inBus, fxBus.index, \useSoundIn, 0, \length, 0.75]);
//
// @meta: (
//   name: \violinResSynth,
//   displayName: "Violin Resonator",
//   parameters: [
//     (name: \length,           default: 0.75, min: 0.05, max: 2.0,   type: \float, label: "String Length (m)"),
//     (name: \position,         default: 0.7,  min: 0.01, max: 0.99,  type: \float, label: "Bow Position (0-1)"),
//     (name: \inputGain,        default: 0.5,  min: 0.0,  max: 2.0,   type: \float, label: "Input Gain"),
//     (name: \outGain,          default: 0.5,  min: 0.0,  max: 2.0,   type: \float, label: "Output Gain"),
//     (name: \mix,              default: 1.0,  min: 0.0,  max: 1.0,   type: \float, label: "Dry/Wet Mix"),
//     (name: \amp,              default: 1.0,  min: 0.0,  max: 2.0,   type: \float, label: "Amplitude"),
//     (name: \pan,              default: 0.0,  min: -1.0, max: 1.0,   type: \float, label: "Pan"),
//     (name: \attack,           default: 0.01, min: 0.001,max: 2.0,   type: \float, label: "Attack (s)"),
//     (name: \release,          default: 0.3,  min: 0.01, max: 5.0,   type: \float, label: "Release (s)"),
//     (name: \stringTuning,     default: 0.08, min: 0.0,  max: 0.5,   type: \float, label: "String Tuning (m)"),
//     (name: \speedOfSound,     default: 340,  min: 100,  max: 1000,  type: \float, label: "Speed of Sound (m/s)"),
//     (name: \lagTime,          default: 0.02, min: 0.001,max: 0.5,   type: \float, label: "Lag Time (s)"),
//     (name: \nutReflCoeff,     default: 0.6,  min: 0.0,  max: 1.0,   type: \float, label: "Nut Refl. Coeff"),
//     (name: \nutT60Scale,      default: 0.1,  min: 0.0,  max: 1.0,   type: \float, label: "Nut T60 Scale"),
//     (name: \bridgeReflCoeff,  default: 0.2,  min: 0.0,  max: 1.0,   type: \float, label: "Bridge Refl. Coeff"),
//     (name: \bridgeT60Scale,   default: 0.9,  min: 0.0,  max: 1.0,   type: \float, label: "Bridge T60 Scale"),
//     (name: \bodyFreq,         default: 500,  min: 50,   max: 5000,  type: \float, label: "Body Freq (Hz)"),
//     (name: \bodyRQ,           default: 0.5,  min: 0.01, max: 2.0,   type: \float, label: "Body RQ"),
//     (name: \bodyGain,         default: 2.0,  min: 0.0,  max: 10.0,  type: \float, label: "Body Gain"),
//     (name: \lengthModRate,    default: 0.0,  min: 0.0,  max: 20.0,  type: \float, label: "Length Mod Rate (Hz)"),
//     (name: \lengthModDepth,   default: 0.0,  min: 0.0,  max: 1.0,   type: \float, label: "Length Mod Depth (m)"),
//     (name: \lengthModType,    default: 0,    min: 0,    max: 3,     type: \int,   label: "Length Mod Type"),
//     (name: \bodyFreqModRate,  default: 0.0,  min: 0.0,  max: 20.0,  type: \float, label: "Body Freq Mod Rate (Hz)"),
//     (name: \bodyFreqModDepth, default: 0.0,  min: 0.0,  max: 2000,  type: \float, label: "Body Freq Mod Depth (Hz)"),
//     (name: \bodyFreqModType,  default: 0,    min: 0,    max: 3,     type: \int,   label: "Body Freq Mod Type"),
//     (name: \posModRate,       default: 0.0,  min: 0.0,  max: 20.0,  type: \float, label: "Pos Mod Rate (Hz)"),
//     (name: \posModDepth,      default: 0.0,  min: 0.0,  max: 0.5,   type: \float, label: "Pos Mod Depth"),
//     (name: \posModType,       default: 0,    min: 0,    max: 3,     type: \int,   label: "Pos Mod Type")
//   ]
// )

SynthDef(\violinResSynth, {
	arg inBus          = 0,     // audio input bus (SoundIn channel or private bus index)
	    useSoundIn     = 1,     // 1 = SoundIn.ar(inBus), 0 = In.ar(inBus) for FX chain
	    outBus         = 0,     // hardware output bus (0 = default stereo out)
	    length         = 0.75,  // string length in metres (-> resonant pitch)
	    position       = 0.7,   // injection point along string (0-1)
	    inputGain      = 0.5,   // gain applied to live input before injection
	    outGain        = 0.5,   // post-body output gain
	    mix            = 1.0,   // dry/wet  0 = input only, 1 = resonated only
	    amp            = 1.0,   // master amplitude
	    pan            = 0,     // stereo pan (-1 to 1)
	    gate           = 1,     // envelope gate
	    attack         = 0.01,  // envelope attack (s)
	    release        = 0.3,   // envelope release (s)
	    // --- string physics ---
	    stringTuning   = 0.08,  // tuning offset subtracted from length (m)
	    speedOfSound   = 340,   // propagation speed (m/s) — scale for creative detuning
	    lagTime        = 0.02,  // smoothing time for length & position changes (s)
	    // --- nut termination filter ---
	    nutReflCoeff   = 0.6,   // nut reflection coefficient (0-1)
	    nutT60Scale    = 0.1,   // nut decay factor (0-1, higher = shorter T60)
	    // --- bridge termination filter ---
	    bridgeReflCoeff = 0.2,  // bridge reflection coefficient (0-1)
	    bridgeT60Scale  = 0.9,  // bridge decay factor (0-1, higher = shorter T60)
	    // --- body resonance ---
	    bodyFreq       = 500,   // body resonance centre frequency (Hz)
	    bodyRQ         = 0.5,   // body reciprocal-Q (bandwidth / freq)
	    bodyGain       = 2.0,   // body resonance output scaling
	    // --- continuous modulation: length ---
	    lengthModRate  = 0,     // Hz (0 = effectively off)
	    lengthModDepth = 0,     // amplitude in metres added to length
	    lengthModType  = 0,     // 0=smooth noise, 1=sine, 2=saw up, 3=saw down
	    // --- continuous modulation: bodyFreq ---
	    bodyFreqModRate  = 0,   // Hz
	    bodyFreqModDepth = 0,   // amplitude in Hz added to bodyFreq
	    bodyFreqModType  = 0,   // 0=smooth noise, 1=sine, 2=saw up, 3=saw down
	    // --- continuous modulation: position ---
	    posModRate  = 0,        // Hz
	    posModDepth = 0,        // amplitude added to position (0-1)
	    posModType  = 0;        // 0=smooth noise, 1=sine, 2=saw up, 3=saw down

	var sr = SampleRate.ir;

	// --- Continuous modulators (depth=0 means no effect) ---
	var lengthMod = Select.kr(lengthModType, [
		LFNoise1.kr(lengthModRate.max(0.001)),
		SinOsc.kr(lengthModRate),
		LFSaw.kr(lengthModRate.max(0.001), 1),
		LFSaw.kr(lengthModRate.max(0.001), 1).neg
	]) * lengthModDepth;

	var bodyFreqMod = Select.kr(bodyFreqModType, [
		LFNoise1.kr(bodyFreqModRate.max(0.001)),
		SinOsc.kr(bodyFreqModRate),
		LFSaw.kr(bodyFreqModRate.max(0.001), 1),
		LFSaw.kr(bodyFreqModRate.max(0.001), 1).neg
	]) * bodyFreqModDepth;

	var posMod = Select.kr(posModType, [
		LFNoise1.kr(posModRate.max(0.001)),
		SinOsc.kr(posModRate),
		LFSaw.kr(posModRate.max(0.001), 1),
		LFSaw.kr(posModRate.max(0.001), 1).neg
	]) * posModDepth;

	// Smoothed controls (modulation added before smoothing)
	var len = Lag.kr(length + lengthMod, lagTime);
	var pos = Lag.kr((position + posMod).clip(0.01, 0.99), lagTime);
	var bFreq = (bodyFreq + bodyFreqMod).max(20);

	// String geometry -> delay lengths in samples
	var stringL     = len - stringTuning;
	var nutToBow    = (stringL * pos * sr / speedOfSound / 2).max(1);
	var bowToBridge = (stringL * (1 - pos) * sr / speedOfSound / 2).max(1);
	var maxDelSec   = 3 / speedOfSound / 2;

	// --- Nut filter coefficients ---
	var nutsH0  = (1.0 + nutReflCoeff) / 2;
	var nutsH1  = (1.0 - nutReflCoeff) / 4;
	var nutsT60 = (1.0 - nutT60Scale) * 20;
	var nutsRho = 0.001.pow(1.0 / (320 * nutsT60));

	// --- Bridge filter coefficients ---
	var brH0  = (1.0 + bridgeReflCoeff) / 2;
	var brH1  = (1.0 - bridgeReflCoeff) / 4;
	var brT60 = (1.0 - bridgeT60Scale) * 20;
	var brRho = 0.001.pow(1.0 / (320 * brT60));

	var dry, excitation;
	var nutRefl, bridgeRefl;
	var leftIn, rightIn;
	var leftDel, rightDel;
	var towardBridge, towardNut;
	var bridgeOut, bodyOut;
	var env, sig;

	dry       = Select.ar(useSoundIn, [In.ar(inBus, 1), SoundIn.ar(inBus)]);
	excitation = dry * inputGain;

	#leftIn, rightIn = LocalIn.ar(2);

	// Left delay line: nut -> injection point
	leftDel = DelayC.ar(leftIn, maxDelSec, nutToBow / sr);

	// Right delay line: bridge -> injection point
	rightDel = DelayC.ar(rightIn, maxDelSec, bowToBridge / sr);

	// Excitation injection
	towardBridge = leftDel  + excitation;
	towardNut    = rightDel + excitation;

	// Bridge termination: reflect through -bridgeFilter
	bridgeRefl = towardBridge;
	bridgeRefl = (brRho * (
		(brH0 * Delay1.ar(bridgeRefl)) +
		(brH1 * (bridgeRefl + Delay2.ar(bridgeRefl)))
	)).neg;

	// Nut termination: reflect through -nutFilter
	nutRefl = towardNut;
	nutRefl = (nutsRho * (
		(nutsH0 * Delay1.ar(nutRefl)) +
		(nutsH1 * (nutRefl + Delay2.ar(nutRefl)))
	)).neg;

	// Feedback
	LocalOut.ar([nutRefl, bridgeRefl]);

	// Bridge output (transmittance = identity)
	bridgeOut = towardBridge;

	// Body resonance filter
	bodyOut = Resonz.ar(bridgeOut, bFreq, bodyRQ) * bodyGain;

	sig = bodyOut * outGain;

	// Dry/wet mix
	sig = (dry * (1 - mix)) + (sig * mix);

	env = EnvGen.kr(
		Env.asr(attack, 1, release),
		gate,
		doneAction: 2
	);

	sig = sig * env * amp;
	sig = LeakDC.ar(sig);
	Out.ar(outBus, Pan2.ar(sig, pan));
}).add;
