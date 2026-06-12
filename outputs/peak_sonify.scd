// Peak Sonify Output Routine
// Creates sustained sine tones at spectral peak frequencies captured by
// a \sineFeature input. Spawns one \peakSonifier synth per peak, then
// releases them all after the specified duration.
//
// @meta: (
//   name: \peakSonify,
//   displayName: "Peak Sonify",
//   category: \output,
//   requiredInputType: \sineFeature,
//   requiredSynthdefs: ["peak_sonifier.scd"],
//   parameters: [
//     (name: \duration, default: 4.0,  min: 0.5,  max: 64,   type: \float, label: "Duration (beats)"),
//     (name: \ampScale, default: 0.1,  min: 0.0,  max: 1.0,  type: \float, label: "Amplitude per voice"),
//     (name: \numVoices,default: 10,   min: 1,    max: 20,   type: \int,   label: "Num Voices"),
//     (name: \attack,   default: 0.02, min: 0.001,max: 2.0,  type: \float, label: "Attack (s)"),
//     (name: \release,  default: 0.3,  min: 0.01, max: 5.0,  type: \float, label: "Release (s)"),
//     (name: \spread,   default: 0.8,  min: 0.0,  max: 1.0,  type: \float, label: "Pan Spread")
//   ]
// )

{ |bufferDict, config, server|
	var outputID, sourceID, triggerBar, triggerBeat, duration;
	var ampScale, numVoices, attack, release, spread;
	var outBus, targetGroup;
	var hasTriggered, synths, oscDefName;

	outputID    = config[\id];
	sourceID    = config[\source];
	triggerBar  = config[\bar];
	triggerBeat = config[\beat];
	duration    = config[\duration]  ? 4.0;
	ampScale    = config[\ampScale]  ? 0.1;
	numVoices   = (config[\numVoices] ? 10).asInteger.clip(1, 20);
	attack      = config[\attack]    ? 0.02;
	release     = config[\release]   ? 0.3;
	spread      = config[\spread]    ? 0.8;
	outBus      = config[\outBus]    ? 0;
	targetGroup = config[\group];

	hasTriggered = false;
	synths       = List.new;
	oscDefName   = ("metro_output_" ++ outputID).asSymbol;

	"[OUTPUT %] Peak Sonify registered: trigger=%:%, source=%, voices=%, duration=%".format(
		outputID, triggerBar, triggerBeat, sourceID, numVoices, duration
	).postln;

	OSCdef(("metro_output_reset_" ++ outputID).asSymbol, { |msg|
		synths.do { |s| try { s.set(\gate, 0); }; };
		synths.clear;
		hasTriggered = false;
		"[OUTPUT %] Reset - released all peak synths".format(outputID).postln;
	}, '/metronome/reset');

	OSCdef(oscDefName, { |msg|
		var bar, beat, bpm;
		bar  = msg[1].asInteger;
		beat = msg[2].asInteger;
		bpm  = msg[3].asInteger;

		if((bar == triggerBar) && (beat == triggerBeat) && hasTriggered.not, {
			var sourceData, freqs, mags, durSec;

			hasTriggered = true;
			durSec = (duration / bpm) * 60;

			"[OUTPUT %] *** TRIGGERED at Bar %:% (% beats = % sec)".format(
				outputID, bar, beat, duration, durSec.round(0.01)
			).postln;

			sourceData = bufferDict[sourceID];

			if(sourceData.isNil, {
				"[OUTPUT %] ERROR: Source % not found in bufferDict!".format(outputID, sourceID).postln;
			}, {
				if(sourceData.isKindOf(Event) && sourceData[\freqs].notNil, {
					freqs = sourceData[\freqs];
					mags  = sourceData[\mags];

					// Limit to requested numVoices
					freqs = freqs.copyFromStart(numVoices - 1);
					mags  = mags.copyFromStart(numVoices - 1);

					"  Sonifying % peaks".format(freqs.size).postln;

					freqs.do { |freq, i|
						var pan, s;
						// Distribute panning evenly across spread range
						pan = (freqs.size > 1).if({
							spread * ((i / (freqs.size - 1)) * 2 - 1)
						}, { 0 });

						s = Synth(\peakSonifier, [
							\freq,    freq.max(20),
							\amp,     ampScale,
							\pan,     pan,
							\gate,    1,
							\outBus,  outBus,
							\attack,  attack,
							\release, release
						], targetGroup ? server);

						synths.add(s);
						"  Voice %: freq=% Hz, pan=%".format(i, freq.round(0.1), pan.round(0.01)).postln;
					};

					// Schedule gate release after duration
					{
						synths.do { |s| try { s.set(\gate, 0); }; };
						"[OUTPUT %] Released % peak synths after % sec".format(
							outputID, synths.size, durSec.round(0.01)
						).postln;
					}.defer(durSec);

				}, {
					"[OUTPUT %] ERROR: Source % is not sineFeature data (got %)".format(
						outputID, sourceID, sourceData.class
					).postln;
				});
			});
		});
	}, '/metronome');

	{
		"[OUTPUT %] Cleanup called".format(outputID).postln;
		synths.do { |s| try { s.free; }; };
		synths.clear;
		try { OSCdef(oscDefName).free; };
		try { OSCdef(("metro_output_reset_" ++ outputID).asSymbol).free; };
	}
}
