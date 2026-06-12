// Flexible Metronome with GUI and OSC Communication
// Handles variable time signatures across bars with multiple cycles

(
var window, startButton, stopButton, patternField, barDisplay, beatDisplay, bpmDisplay;
var cycleDisplay, repeatDisplay, oscIPField, oscPortField, statusText;
var tempoClock, metroTask, metroRunning, synthDef;
var pattern, currentCycleIdx, currentRepeatCount, currentBarIdx, currentBeatIdx;
var totalCyclesPlayed, oscNetAddr, currentBPM;
var beatIndicator, beatIndicatorContainer, beatIndicatorBoxes, oscSendEnabled, loopForever, muteEnabled;

// Default pattern
pattern = [
	(b: [4], r: 10, bpm: 100)
];

// Initialize state variables
metroRunning = false;
currentCycleIdx = 0;
currentRepeatCount = 0;
currentBarIdx = 0;
currentBeatIdx = -1;
totalCyclesPlayed = 0;
currentBPM = 100;
oscSendEnabled = true;
loopForever = true;
muteEnabled = false;

// Audio Server Setup
s.waitForBoot({

	// Define Click SynthDef
	synthDef = SynthDef(\metroClick, {
		arg freq = 1000, amp = 0.5, dur = 0.05;
		var env, sig;
		env = EnvGen.kr(Env.perc(0.001, dur), doneAction: 2);
		sig = SinOsc.ar(freq) * env * amp;
		Out.ar(0, sig ! 2);
	}).add;

	s.sync;

	// OSC Network Address (localhost by default, change to your network IP for LAN broadcast)
	// For LAN broadcast, use your network's broadcast address (e.g., "192.168.1.255")
	oscNetAddr = NetAddr("127.0.0.1", 57120);

	// Function to normalize pattern with default values
	~normalizePattern = {
		arg pat;
		pat.collect { |cycle|
			(
				b: cycle[\b],
				r: cycle[\r] ?? 1,  // default repeat = 1
				bpm: cycle[\bpm] ?? 80  // default bpm = 80
			);
		};
	};

	// Function to parse and validate pattern
	~validatePattern = {
		arg pat;
		var valid = true;
		if(pat.isNil || (pat.size == 0), {
			"Pattern is empty or invalid".postln;
			valid = false;
		}, {
			pat.do { |cycle, idx|
				if(cycle[\b].isNil, {
					"Cycle % is missing required key 'b' (bars array)".format(idx).postln;
					valid = false;
				});
				if(cycle[\b].notNil && (cycle[\b].size == 0), {
					"Cycle % has empty bars array".format(idx).postln;
					valid = false;
				});
			};
		});
		valid;
	};

	// Function to get current bar's beat count
	~getCurrentBarBeats = {
		if(currentCycleIdx < pattern.size, {
			pattern[currentCycleIdx][\b][currentBarIdx];
		}, {
			4; // default fallback
		});
	};

	// Function to update beat indicator layout
	~updateBeatIndicatorLayout = {
		var numBeats;

		numBeats = ~getCurrentBarBeats.value;

		{
			if(beatIndicatorBoxes.notNil, {
				// Show/hide boxes based on current bar's beat count
				beatIndicatorBoxes.do { |box, i|
					if(i < numBeats, {
						box.visible = true;
					}, {
						box.visible = false;
					});
					box.background = Color.gray;
				};
			});
		}.defer;
	};

	// Function to update beat indicator position
	~updateBeatIndicatorPosition = {
		{
			if(beatIndicatorBoxes.notNil, {
				// Reset all boxes to gray
				beatIndicatorBoxes.do { |box|
					box.background = Color.gray;
				};

				// Highlight current beat
				if(currentBeatIdx >= 0 && (currentBeatIdx < beatIndicatorBoxes.size), {
					beatIndicatorBoxes[currentBeatIdx].background = Color.red;
				});
			});
		}.defer;
	};

	// Function to advance to next beat
	~advanceBeat = {
		var currentCycle, currentBarBeats, totalBarsInCycle, oldBarIdx, shouldStop;

		shouldStop = false;
		currentCycle = pattern[currentCycleIdx];
		currentBarBeats = currentCycle[\b][currentBarIdx];
		totalBarsInCycle = currentCycle[\b].size;
		oldBarIdx = currentBarIdx;

		currentBeatIdx = currentBeatIdx + 1;

		// Check if we've completed the current bar
		if(currentBeatIdx >= currentBarBeats, {
			currentBeatIdx = 0;
			currentBarIdx = currentBarIdx + 1;

			// Check if we've completed all bars in the cycle
			if(currentBarIdx >= totalBarsInCycle, {
				currentBarIdx = 0;
				currentRepeatCount = currentRepeatCount + 1;

				// Check if we've completed all repeats of the cycle
				if(currentRepeatCount >= currentCycle[\r], {
					currentRepeatCount = 0;
					currentCycleIdx = currentCycleIdx + 1;

					// Check if we've completed all cycles
					if(currentCycleIdx >= pattern.size, {
						if(loopForever, {
							// Loop back to beginning
							currentCycleIdx = 0;
							totalCyclesPlayed = totalCyclesPlayed + 1;
							~sendResetOSC.value;
						}, {
							// Mark for stopping after this beat
							shouldStop = true;
							currentCycleIdx = 0; // Reset for next time
						});
					});

					// Update BPM for new cycle (if still running)
					if(shouldStop.not && (currentCycleIdx < pattern.size), {
						currentBPM = pattern[currentCycleIdx][\bpm];
						tempoClock.tempo = currentBPM / 60.0;
					});
				});
			});

			// Update beat indicator layout when bar changes
			if(oldBarIdx != currentBarIdx, {
				~updateBeatIndicatorLayout.value;
			});
		});

		// Return whether we should stop
		shouldStop;
	};

	// Function to play click sound
	~playClick = {
		if(muteEnabled.not, {
			var isDownbeat = (currentBeatIdx == 0);
			var freq = if(isDownbeat, { 1200 }, { 800 });
			var amp = if(isDownbeat, { 0.7 }, { 0.4 });
			Synth(\metroClick, [\freq, freq, \amp, amp, \dur, 0.05]);
		});
	};

	// Function to send OSC message
	~sendOSC = {
		var globalBarNumber, beatsBeforeCurrentCycle, i, cycle;

		if(oscSendEnabled && oscNetAddr.notNil, {
			// Calculate global bar number
			globalBarNumber = 1;
			beatsBeforeCurrentCycle = 0;

			// Add bars from previous cycles
			i = 0;
			while({ i < currentCycleIdx }, {
				cycle = pattern[i];
				globalBarNumber = globalBarNumber + (cycle[\b].size * cycle[\r]);
				i = i + 1;
			});

			// Add bars from current cycle's previous repeats
			globalBarNumber = globalBarNumber + (currentBarIdx + (currentRepeatCount * pattern[currentCycleIdx][\b].size));

			// Send OSC message: /metronome [bar, beat, bpm]
			oscNetAddr.sendMsg('/metronome', globalBarNumber, currentBeatIdx + 1, currentBPM);
		});
	};

	// Send explicit reset notification to all listening routines.
	// Routines subscribe to /metronome/reset and use it to re-arm one-shot state
	// (isComplete, hasTriggered, etc.) without needing to infer reset from bar numbers.
	~sendResetOSC = {
		if(oscSendEnabled && oscNetAddr.notNil, {
			oscNetAddr.sendMsg('/metronome/reset');
			"Metronome reset OSC sent -> /metronome/reset".postln;
		});
	};

	// Function to update GUI displays
	~updateGUI = {
		var globalBarNumber, cycle;

		// Calculate global bar number for display
		globalBarNumber = 1;
		cycle = 0;
		while({ cycle < currentCycleIdx }, {
			globalBarNumber = globalBarNumber + (pattern[cycle][\b].size * pattern[cycle][\r]);
			cycle = cycle + 1;
		});
		globalBarNumber = globalBarNumber + (currentBarIdx + (currentRepeatCount * pattern[currentCycleIdx][\b].size));

		{
			barDisplay.value = globalBarNumber;
			beatDisplay.value = currentBeatIdx + 1;
			bpmDisplay.value = currentBPM;
			cycleDisplay.value = currentCycleIdx + 1;
			repeatDisplay.value = currentRepeatCount + 1;
		}.defer;

		// Update beat indicator position
		~updateBeatIndicatorPosition.value;

		// Post to console
		"Cycle: % | Repeat: %/% | Bar: % | Beat: %/% | BPM: %".format(
			currentCycleIdx + 1,
			currentRepeatCount + 1,
			pattern[currentCycleIdx][\r],
			globalBarNumber,
			currentBeatIdx + 1,
			pattern[currentCycleIdx][\b][currentBarIdx],
			currentBPM
		).postln;
	};

	// Metro callback function - advance counters, then update/display, play, and OSC
	~metroBeat = {
		var shouldStop;
		shouldStop = ~advanceBeat.value;
		~updateGUI.value;
		~playClick.value;
		~sendOSC.value;

		// Stop after this beat if pattern is complete and not looping
		if(shouldStop, {
			{
				~stopMetronome.value;
				statusText.string = "Completed";
				statusText.stringColor = Color.blue;
				"Pattern completed - metronome stopped".postln;
			}.defer(0.1); // Small delay to ensure this beat completes
		});
	};

	// Create TempoClock
	tempoClock = TempoClock.new(currentBPM / 60.0);

	// Function to start metronome
	~startMetronome = {
		if(~validatePattern.value(pattern), {
			if(metroRunning.not, {
				// Normalize pattern with defaults
				pattern = ~normalizePattern.value(pattern);
				currentBPM = pattern[currentCycleIdx][\bpm];
				tempoClock.tempo = currentBPM / 60.0;

				metroTask = Task({
					inf.do {
						~metroBeat.value;
						1.wait; // Wait 1 beat
					};
				}, tempoClock);

				metroTask.start;
				metroRunning = true;
				{
					startButton.enabled = false;
					stopButton.enabled = true;
					statusText.string = "Running";
					statusText.stringColor = Color.green;
				}.defer;
				"Metronome started".postln;
			});
		}, {
			{
				statusText.string = "Invalid Pattern!";
				statusText.stringColor = Color.red;
			}.defer;
		});
	};

	// Function to stop metronome
	~stopMetronome = {
		if(metroRunning, {
			if(metroTask.notNil, {
				metroTask.stop;
			});
			metroRunning = false;
			{
				startButton.enabled = true;
				stopButton.enabled = false;
				statusText.string = "Stopped";
				statusText.stringColor = Color.red;
			}.defer;
			"Metronome stopped".postln;
		});
	};

	// Function to reset metronome
	~resetMetronome = {
		var wasRunning;
		wasRunning = metroRunning;
		
		~stopMetronome.value;
		currentCycleIdx = 0;
		currentRepeatCount = 0;
		currentBarIdx = 0;
		currentBeatIdx = -1;
		totalCyclesPlayed = 0;
		currentBPM = pattern[0][\bpm];

		// Recreate TempoClock to avoid "clock is not running" error
		tempoClock = TempoClock.new(currentBPM / 60.0);

		~updateBeatIndicatorLayout.value;
		~updateGUI.value;
		"Metronome reset".postln;

		// Notify all routines that the metronome has reset so they can re-arm
		// their one-shot state (isComplete, hasTriggered, etc.)
		~sendResetOSC.value;
		
		// If it was running, restart it
		if(wasRunning, {
			~startMetronome.value;
		});
	};

	// Function to parse pattern from text
	~parsePatternText = {
		arg text;
		var parsedPattern;
		try {
			parsedPattern = text.interpret;
			if(~validatePattern.value(parsedPattern), {
				pattern = ~normalizePattern.value(parsedPattern);
				~resetMetronome.value;
				{
					statusText.string = "Pattern Loaded";
					statusText.stringColor = Color.green;
				}.defer;
				"Pattern loaded successfully".postln;
			}, {
				{
					statusText.string = "Invalid Pattern Format";
					statusText.stringColor = Color.red;
				}.defer;
			});
		} {
			{
				statusText.string = "Parse Error";
				statusText.stringColor = Color.red;
			}.defer;
			"Pattern parse error".postln;
		};
	};

	// Function to update OSC address
	~updateOSCAddress = {
		var ip, port;
		ip = oscIPField.string;
		port = oscPortField.string.asInteger;
		try {
			oscNetAddr = NetAddr(ip, port);
			{
				statusText.string = "OSC Updated: %:%".format(ip, port);
				statusText.stringColor = Color.blue;
			}.defer;
			"OSC address updated: %:%".format(ip, port).postln;
		} {
			{
				statusText.string = "OSC Address Error";
				statusText.stringColor = Color.red;
			}.defer;
		};
	};

	// Create GUI
	window = Window("Metronome", Rect(100, 100, 600, 500))
		.onClose_({ ~stopMetronome.value; });

	window.layout = VLayout(
		// Title
		StaticText().string_("Metronome").align_(\center).font_(Font.default.size_(20)),

	// Control buttons
	HLayout(
		startButton = Button()
			.states_([["Start", Color.black, Color.green]])
			.action_({ ~startMetronome.value; }),
		stopButton = Button()
			.states_([["Stop", Color.white, Color.red]])
			.action_({ ~stopMetronome.value; })
			.enabled_(false),
		Button()
			.states_([["Reset", Color.black, Color.yellow]])
			.action_({ ~resetMetronome.value; }),
		CheckBox()
			.value_(true)
			.action_({ arg checkbox; loopForever = checkbox.value; })
			.string_("Loop Forever"),
		CheckBox()
			.value_(false)
			.action_({ arg checkbox; muteEnabled = checkbox.value; })
			.string_("Mute")
	),

		// Status display
		HLayout(
			StaticText().string_("Status:"),
			statusText = StaticText()
				.string_("Stopped")
				.stringColor_(Color.red)
				.font_(Font.default.size_(14))
		),

		// Visual beat indicator
		HLayout(
			StaticText().string_("Beat Indicator:").minWidth_(100),
			beatIndicatorContainer = HLayout().spacing_(5)
		),

		// Current state display
		HLayout(
			VLayout(
				StaticText().string_("Cycle"),
				cycleDisplay = NumberBox().value_(1).enabled_(false)
			),
			VLayout(
				StaticText().string_("Repeat"),
				repeatDisplay = NumberBox().value_(1).enabled_(false)
			),
			VLayout(
				StaticText().string_("Bar"),
				barDisplay = NumberBox().value_(1).enabled_(false)
			),
			VLayout(
				StaticText().string_("Beat"),
				beatDisplay = NumberBox().value_(1).enabled_(false)
			),
			VLayout(
				StaticText().string_("BPM"),
				bpmDisplay = NumberBox().value_(100).enabled_(false)
			)
		),

		// Pattern editor
		VLayout(
			StaticText().string_("Pattern Editor [(b: [v1, v2], r: v, bpm: v), () ...] (r defaults to 1, bpm defaults to 80):"),
			patternField = TextView()
				.string_("[(b: [4], r: 10, bpm: 100)]")
				.minHeight_(100)
				.font_(Font.monospace.size_(11)),
			Button()
				.states_([["Load Pattern", Color.black, Color.cyan]])
				.action_({ ~parsePatternText.value(patternField.string); })
		),

		// OSC Configuration
		VLayout(
			StaticText().string_("OSC Configuration:"),
			HLayout(
				StaticText().string_("IP:"),
				oscIPField = TextField()
					.string_("127.0.0.1")
					.minWidth_(150),
				StaticText().string_("Port:"),
				oscPortField = TextField()
					.string_("57120")
					.minWidth_(80),
				Button()
					.states_([["Update OSC", Color.black, Color.cyan]])
					.action_({ ~updateOSCAddress.value; })
			),
			HLayout(
				CheckBox()
					.value_(true)
					.action_({ arg checkbox; oscSendEnabled = checkbox.value; })
					.string_("Enable OSC Broadcasting")
			)
		)
	);

	window.front;

	// Create beat indicator boxes (max 12 beats to handle most time signatures)
	beatIndicatorBoxes = Array.fill(12, { |i|
		var box;
		box = UserView()
			.minWidth_(40)
			.maxWidth_(40)
			.minHeight_(30)
			.background_(Color.gray);
		beatIndicatorContainer.add(box);
		box;
	});

	// Initialize beat indicator with first bar's beats
	~updateBeatIndicatorLayout.value;

	"Flexible Metronome GUI loaded successfully".postln;
	"Pattern format: [(b: [beats...], r: repeats, bpm: tempo), ...]".postln;
	"  - 'b' (required): array of beat counts per bar".postln;
	"  - 'r' (optional, default=1): number of times to repeat the cycle".postln;
	"  - 'bpm' (optional, default=80): tempo in beats per minute".postln;
	"OSC message format: /metronome [bar, beat, bpm]".postln;
});
)
