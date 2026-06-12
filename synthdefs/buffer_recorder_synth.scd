// Buffer Recorder SynthDef
// Records audio input to a buffer using RecordBuf
//
// @meta: (
//   name: \bufferRecordInputSynth,
//   displayName: "Buffer Recorder",
//   parameters: [
//     (name: \amp, default: 1.0, min: 0.0, max: 2.0, type: \float, label: "Input Gain")
//   ]
// )

SynthDef(\bufferRecordInputSynth, { |inBus = 0, bufNum = 0, amp = 1.0|
	var sig;
	sig = SoundIn.ar(inBus) * amp;
	RecordBuf.ar(sig, bufNum, loop: 0, doneAction: 2);
}).add;
