// Pitch Shift Output Routine
// Applies live audio pitch shifting using PitchShift. No source buffer
// needed — it processes live audio from the audio input bus.
// The synth runs for the specified duration then is released via gate.
//
// @meta: (
//   name: \pitchShift,
//   displayName: "Pitch Shift",
//   category: \output,
//   requiredInputType: nil,
//   requiredSynthdefs: ["pitch_shift_synth.scd"],
//   parameters: [
//     (name: \duration,   default: 4.0,  min: 0.5,  max: 64,   type: \float, label: "Duration (beats)"),
//     (name: \pitchRatio, default: 1.0,  min: 0.25, max: 4.0,  type: \float, label: "Pitch Ratio"),
//     (name: \windowSize, default: 0.2,  min: 0.01, max: 1.0,  type: \float, label: "Window Size (s)"),
//     (name: \pitchDisp,  default: 0.0,  min: 0.0,  max: 1.0,  type: \float, label: "Pitch Dispersion"),
//     (name: \timeDisp,   default: 0.0,  min: 0.0,  max: 1.0,  type: \float, label: "Time Dispersion"),
//     (name: \ampScale,   default: 0.5,  min: 0.0,  max: 2.0,  type: \float, label: "Amplitude"),
//     (name: \pan,        default: 0.0,  min: -1.0, max: 1.0,  type: \float, label: "Pan"),
//     (name: \attack,     default: 0.01, min: 0.001,max: 2.0,  type: \float, label: "Attack (s)"),
//     (name: \release,    default: 0.3,  min: 0.01, max: 5.0,  type: \float, label: "Release (s)")
//   ]
// )

{ |bufferDict, config, server, audioInputBus|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var pitchRatio, windowSize, pitchDisp, timeDisp, ampScale, pan, attack, release;
	var outBus, targetGroup;
	var hasTriggered, synth, oscDefName;

	outputID    = config[\id];
	sourceID    = config[\source];
	triggerBar  = config[\bar];
	triggerBeat = config[\beat];
	duration    = config[\duration]   ? 4.0;
	pitchRatio  = config[\pitchRatio] ? 1.0;
	windowSize  = config[\windowSize] ? 0.2;
	pitchDisp   = config[\pitchDisp]  ? 0.0;
	timeDisp    = config[\timeDisp]   ? 0.0;
	ampScale    = config[\ampScale]   ? 0.5;
	pan         = config[\pan]        ? 0;
	attack      = config[\attack]     ? 0.01;
	release     = config[\release]    ? 0.3;
	outBus      = config[\outBus]     ? 0;
	targetGroup = config[\group];

	hasTriggered = false;
	synth        = nil;
	oscDefName   = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Pitch Shift registered: trigger=%:%, pitchRatio=%, duration=% beats".format(
		outputID, triggerBar, triggerBeat, pitchRatio, duration
	).postln;

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		if(synth.notNil, {
			try { synth.set(\gate, 0); };
			synth = nil;
			"[OUTPUT %] Reset - released pitch shift synth".format(outputID).postln;
		});
		hasTriggered = false;
		"[OUTPUT %] Reset - ready at %:%".format(outputID, triggerBar, triggerBeat).postln;
	}, '/metronome/reset');

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;
		bar  = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm  = msg[3].asInteger;

		if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
			var durSec;

			hasTriggered = true;
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (% beats = % sec at % BPM)".format(
				outputID, bar, beat, duration, durSec.round(0.01), bpm
			).postln;

			synth = Synth(\pitchShiftSynth, [
				\inBus,       audioInputBus ? 0,
				\useSoundIn,  1,
				\outBus,      outBus,
				\pitchRatio,  pitchRatio,
				\windowSize,  windowSize,
				\pitchDisp,   pitchDisp,
				\timeDisp,    timeDisp,
				\amp,         ampScale,
				\pan,         pan,
				\gate,        1,
				\attack,      attack,
				\release,     release
			], targetGroup ? server);

			"  Pitch shift started: ratio=%, winSize=% sec, duration=% sec".format(
				pitchRatio, windowSize, durSec.round(0.01)
			).postln;

			// Schedule gate release after duration
			{
				if(synth.notNil, {
					try { synth.set(\gate, 0); };
					synth = nil;
					"[OUTPUT %] Released pitch shift synth after % sec".format(outputID, durSec.round(0.01)).postln;
				});
			}.defer(durSec);
		});
	}, '/metronome');

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;
		if(synth.notNil, {
			try { synth.set(\gate, 0); };
			synth = nil;
		});
		try { OSCdef(oscDefName).free; };
		try { OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free; };
	}
}
