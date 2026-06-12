// Violin Resonator Input Routine
// Runs live audio through the violin waveguide resonator model.
// Supports two layers of parameter control:
//   1. Beat-quantized automations: generic 'automations' array in config
//      (modes: random, ramp, sequence) -- calls synth.set() each beat
//   2. Continuous modulation: lengthModRate/Depth/Type etc. passed at
//      synth creation and running server-side as UGens
//
// @meta: (
//   name: \violinRes,
//   displayName: "Violin Resonator",
//   category: \input,
//   requiredSynthdefs: ["violin_res_synth.scd"],
//   parameters: [
//     (name: \length,           default: 0.75, min: 0.05, max: 2.0,  type: \float, label: "String Length (m)"),
//     (name: \position,         default: 0.7,  min: 0.01, max: 0.99, type: \float, label: "Injection Position"),
//     (name: \inputGain,        default: 0.5,  min: 0,    max: 2.0,  type: \float, label: "Input Gain"),
//     (name: \outGain,          default: 0.5,  min: 0,    max: 2.0,  type: \float, label: "Output Gain"),
//     (name: \mix,              default: 1.0,  min: 0,    max: 1.0,  type: \float, label: "Dry/Wet Mix"),
//     (name: \amp,              default: 1.0,  min: 0,    max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,              default: 0,    min: -1,   max: 1,    type: \float, label: "Pan"),
//     (name: \attack,           default: 0.01, min: 0.001,max: 2.0,  type: \float, label: "Attack (s)"),
//     (name: \release,          default: 0.3,  min: 0.01, max: 5.0,  type: \float, label: "Release (s)"),
//     (name: \stringTuning,     default: 0.08, min: 0,    max: 0.5,  type: \float, label: "String Tuning Offset (m)"),
//     (name: \speedOfSound,     default: 340,  min: 100,  max: 1000, type: \float, label: "Speed of Sound (m/s)"),
//     (name: \lagTime,          default: 0.02, min: 0.001,max: 1.0,  type: \float, label: "Param Lag Time (s)"),
//     (name: \nutReflCoeff,     default: 0.6,  min: 0,    max: 1.0,  type: \float, label: "Nut Refl Coeff"),
//     (name: \nutT60Scale,      default: 0.1,  min: 0,    max: 0.99, type: \float, label: "Nut T60 Scale"),
//     (name: \bridgeReflCoeff,  default: 0.2,  min: 0,    max: 1.0,  type: \float, label: "Bridge Refl Coeff"),
//     (name: \bridgeT60Scale,   default: 0.9,  min: 0,    max: 0.99, type: \float, label: "Bridge T60 Scale"),
//     (name: \bodyFreq,         default: 500,  min: 50,   max: 5000, type: \float, label: "Body Freq (Hz)"),
//     (name: \bodyRQ,           default: 0.5,  min: 0.01, max: 2.0,  type: \float, label: "Body RQ"),
//     (name: \bodyGain,         default: 2.0,  min: 0,    max: 10.0, type: \float, label: "Body Gain"),
//     (name: \lengthModRate,    default: 0,    min: 0,    max: 20,   type: \float, label: "Length Mod Rate (Hz)"),
//     (name: \lengthModDepth,   default: 0,    min: 0,    max: 1.0,  type: \float, label: "Length Mod Depth (m)"),
//     (name: \lengthModType,    default: 0,    min: 0,    max: 3,    type: \int,   label: "Length Mod Type (0-3)"),
//     (name: \bodyFreqModRate,  default: 0,    min: 0,    max: 20,   type: \float, label: "BodyFreq Mod Rate (Hz)"),
//     (name: \bodyFreqModDepth, default: 0,    min: 0,    max: 2000, type: \float, label: "BodyFreq Mod Depth (Hz)"),
//     (name: \bodyFreqModType,  default: 0,    min: 0,    max: 3,    type: \int,   label: "BodyFreq Mod Type (0-3)"),
//     (name: \posModRate,       default: 0,    min: 0,    max: 20,   type: \float, label: "Position Mod Rate (Hz)"),
//     (name: \posModDepth,      default: 0,    min: 0,    max: 0.5,  type: \float, label: "Position Mod Depth"),
//     (name: \posModType,       default: 0,    min: 0,    max: 3,    type: \int,   label: "Position Mod Type (0-3)"),
//     (name: \automations,      default: [],                          type: \array, label: "Beat Automations")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var inputID, startBar, startBeat, durationBeats;
	var elapsedBeats, isActive, isComplete;
	var synth, oscDefName;
	var bar, beat, bpm;
	var automations;
	var fxInBus, pUseSoundIn, targetGroup, pOutBus;
	// SynthDef args
	var pLength, pPosition, pInputGain, pOutGain, pMix, pAmp, pPan;
	var pAttack, pRelease, pStringTuning, pSpeedOfSound, pLagTime;
	var pNutReflCoeff, pNutT60Scale, pBridgeReflCoeff, pBridgeT60Scale;
	var pBodyFreq, pBodyRQ, pBodyGain;
	// Modulation args
	var pLengthModRate, pLengthModDepth, pLengthModType;
	var pBodyFreqModRate, pBodyFreqModDepth, pBodyFreqModType;
	var pPosModRate, pPosModDepth, pPosModType;

	// Extract standard config fields
	inputID       = config[\id];
	startBar      = config[\startBar];
	startBeat     = config[\startBeat];
	durationBeats = config[\durationBeats];

	// FX chain routing (injected by routines.scd when fxChains is configured)
	fxInBus      = config[\fxInBus];
	pUseSoundIn  = config[\useSoundIn] ? 1;
	targetGroup  = config[\group];
	pOutBus      = config[\outBus] ? 0;

	// Extract SynthDef parameters with defaults
	pLength          = config[\length]          ? 0.75;
	pPosition        = config[\position]        ? 0.7;
	pInputGain       = config[\inputGain]       ? 0.5;
	pOutGain         = config[\outGain]         ? 0.5;
	pMix             = config[\mix]             ? 1.0;
	pAmp             = config[\amp]             ? 1.0;
	pPan             = config[\pan]             ? 0;
	pAttack          = config[\attack]          ? 0.01;
	pRelease         = config[\release]         ? 0.3;
	pStringTuning    = config[\stringTuning]    ? 0.08;
	pSpeedOfSound    = config[\speedOfSound]    ? 340;
	pLagTime         = config[\lagTime]         ? 0.02;
	pNutReflCoeff    = config[\nutReflCoeff]    ? 0.6;
	pNutT60Scale     = config[\nutT60Scale]     ? 0.1;
	pBridgeReflCoeff = config[\bridgeReflCoeff] ? 0.2;
	pBridgeT60Scale  = config[\bridgeT60Scale]  ? 0.9;
	pBodyFreq        = config[\bodyFreq]        ? 500;
	pBodyRQ          = config[\bodyRQ]          ? 0.5;
	pBodyGain        = config[\bodyGain]        ? 2.0;

	// Extract modulation parameters with defaults (0 = off)
	pLengthModRate    = config[\lengthModRate]    ? 0;
	pLengthModDepth   = config[\lengthModDepth]   ? 0;
	pLengthModType    = config[\lengthModType]    ? 0;
	pBodyFreqModRate  = config[\bodyFreqModRate]  ? 0;
	pBodyFreqModDepth = config[\bodyFreqModDepth] ? 0;
	pBodyFreqModType  = config[\bodyFreqModType]  ? 0;
	pPosModRate       = config[\posModRate]       ? 0;
	pPosModDepth      = config[\posModDepth]      ? 0;
	pPosModType       = config[\posModType]       ? 0;

	// Extract automations array (empty = no beat-quantized updates)
	automations = config[\automations] ? [];

	// State
	elapsedBeats = 0;
	isActive = false;
	isComplete = false;
	synth = nil;

	oscDefName = ("metro_input_" ++ inputID).asSymbol;

	"[INPUT %] Violin Resonator registered: startBar=%, startBeat=%, duration=% beats, automations=%".format(
		inputID, startBar, startBeat, durationBeats, automations.size
	).postln;

	// =========================================================================
	// RESET LISTENER  (/metronome/reset)
	// =========================================================================

	OSCdef(("metro_input_reset_" ++ inputID).asSymbol, { |msg|
		if(synth.notNil, {
			synth.set(\gate, 0);
			synth = nil;
			"[INPUT %] Reset - released violin resonator synth".format(inputID).postln;
		});
		isActive = false;
		isComplete = false;
		elapsedBeats = 0;
		"[INPUT %] Reset - ready to start again at %:%".format(inputID, startBar, startBeat).postln;
	}, '/metronome/reset');

	// =========================================================================
	// METRONOME LISTENER
	// =========================================================================

	OSCdef(oscDefName, { |msg|
		var autoParam, autoMode, autoVal, autoVals;

		bar = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm = msg[3].asInteger;

		// START
		if((bar.asInteger == startBar.asInteger) && (beat.asInteger == startBeat.asInteger) && isActive.not && isComplete.not, {
			isActive = true;
			elapsedBeats = 0;

			"[INPUT %] >>> STARTED violin resonator at Bar %:%".format(inputID, bar, beat).postln;

		synth = Synth(\violinResSynth, [
			\inBus,            fxInBus ? audioInputBus,
			\useSoundIn,       pUseSoundIn,
			\outBus,           pOutBus,
			\length,           pLength,
			\position,         pPosition,
			\inputGain,        pInputGain,
			\outGain,          pOutGain,
			\mix,              pMix,
			\amp,              pAmp,
			\pan,              pPan,
			\attack,           pAttack,
			\release,          pRelease,
			\stringTuning,     pStringTuning,
			\speedOfSound,     pSpeedOfSound,
			\lagTime,          pLagTime,
			\nutReflCoeff,     pNutReflCoeff,
			\nutT60Scale,      pNutT60Scale,
			\bridgeReflCoeff,  pBridgeReflCoeff,
			\bridgeT60Scale,   pBridgeT60Scale,
			\bodyFreq,         pBodyFreq,
			\bodyRQ,           pBodyRQ,
			\bodyGain,         pBodyGain,
			\lengthModRate,    pLengthModRate,
			\lengthModDepth,   pLengthModDepth,
			\lengthModType,    pLengthModType,
			\bodyFreqModRate,  pBodyFreqModRate,
			\bodyFreqModDepth, pBodyFreqModDepth,
			\bodyFreqModType,  pBodyFreqModType,
			\posModRate,       pPosModRate,
			\posModDepth,      pPosModDepth,
			\posModType,       pPosModType
		], targetGroup ? server);

			"[INPUT %] Synth created".format(inputID).postln;
		});

		// COUNT, AUTOMATE & STOP
		if(isActive, {

			// --- Beat-quantized automations ---
			if(synth.notNil, {
				automations.do { |auto|
					autoParam = auto[\param].asSymbol;
					autoMode  = auto[\mode].asSymbol;
					autoVal   = nil;

					switch(autoMode,
						\random, {
							autoVal = rrand(auto[\min].asFloat, auto[\max].asFloat);
						},
						\ramp, {
							autoVal = auto[\from].asFloat
								+ ((auto[\to].asFloat - auto[\from].asFloat)
								* (elapsedBeats / (durationBeats - 1).max(1)));
						},
						\sequence, {
							autoVals = auto[\values];
							autoVal  = autoVals[elapsedBeats % autoVals.size];
						}
					);

					if(autoVal.notNil, {
						synth.set(autoParam, autoVal);
					});
				};
			});

			elapsedBeats = elapsedBeats + 1;

			// STOP when duration reached
			if(elapsedBeats >= durationBeats, {
				isActive = false;
				isComplete = true;

				"[INPUT %] <<< STOPPED violin resonator at Bar %:% (elapsed: % beats)".format(
					inputID, bar, beat, elapsedBeats
				).postln;

				if(synth.notNil, {
					synth.set(\gate, 0);
					synth = nil;
				});
			});
		});
	}, '/metronome');

	// =========================================================================
	// CLEANUP FUNCTION
	// =========================================================================

	{
		"[INPUT %] Cleanup called".format(inputID).postln;

		if(synth.notNil, {
			synth.set(\gate, 0);
			synth = nil;
			"  Released violin resonator synth".postln;
		});

		OSCdef(oscDefName).free;
		"  Freed OSCdef: %".format(oscDefName).postln;
		OSCdef(("metro_input_reset_" ++ inputID).asSymbol).free;
		"  Freed reset OSCdef: metro_input_reset_%".format(inputID).postln;
	}
}
