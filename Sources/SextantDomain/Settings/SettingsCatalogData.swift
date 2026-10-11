// Generated from design/PrototypeKit/Sources/PrototypeKit/Resources/settings-catalog.json (ADR 0008).
// Setting ids, types, defaults and ranges follow Oryx; titles and descriptions are Sextant's own.
// swift-format-ignore-file

enum SettingsCatalogData {
    static let json = #"""
{
 "format": 1,
 "board": "voyager",
 "about": "Setting ids, types, defaults and ranges follow Oryx's settings catalog (fetched 2026-10-11) so imported configs map 1:1. Titles and descriptions are Sextant's own. Debounce shows the Voyager default. Oryx stores config sparsely: a missing key means the default. Trackball sensitivity is Sextant's (ADR 0035): Oryx keeps it outside its catalog, so its default and range are the trackball module's.",
 "settingCount": 101,
 "sections": [
  {
   "id": "autoshift",
   "title": "Auto Shift",
   "summary": "Hold a key a little longer to type its shifted character.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "autoshift",
     "title": "Auto Shift",
     "summary": "Turns Auto Shift on. Holding a key past the delay sends its shifted version. Keys that already have a hold action are not affected.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "autoshiftTimeout",
     "title": "Auto Shift delay",
     "summary": "How long a key must be held before it is shifted. Lower is quicker but causes more accidental capitals; most people settle between 135 and 175 ms.",
     "type": "slider",
     "default": 175,
     "min": 50,
     "max": 350,
     "unit": "milliseconds"
    },
    {
     "id": "autoshiftModifiers",
     "title": "Auto Shift with modifiers",
     "summary": "Also apply Auto Shift while another modifier is held. When off, a long ⌃A stays ⌃A.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "autoshiftEnableSpecial",
     "title": "Shift punctuation keys",
     "summary": "Apply Auto Shift to punctuation such as - = [ ] ; ' , . and /.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "autoshiftEnableNumeric",
     "title": "Shift number keys",
     "summary": "Apply Auto Shift to 0–9, so a long press on 1 types !.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "autoshiftEnableAlpha",
     "title": "Shift letter keys",
     "summary": "Apply Auto Shift to A–Z. Turn it off to keep Auto Shift for numbers and symbols only.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "autoshiftEnableTab",
     "title": "Shift Tab",
     "summary": "Apply Auto Shift to Tab, so a long press sends ⇧⇥.",
     "type": "toggle",
     "default": true
    }
   ]
  },
  {
   "id": "audio",
   "title": "Audio",
   "summary": "Buzzer options. The ZSA Voyager has no buzzer, so Oryx hides this section for it.",
   "visibleOnVoyager": false,
   "settings": [
    {
     "id": "audioDisable",
     "title": "Silence buzzer",
     "summary": "Mute every sound, including the start-up tune. Boards with a buzzer only.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "audioClick",
     "title": "Key click sound",
     "summary": "Play a short click on every key press. Boards with a buzzer only.",
     "type": "toggle",
     "default": false
    }
   ]
  },
  {
   "id": "combo",
   "title": "Combos",
   "summary": "Timing for chords of keys that act together as one key.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "comboTerm",
     "title": "Combo window",
     "summary": "How close together the keys of a combo must go down. Raise it if combos are hard to hit; lower it if they fire by accident.",
     "type": "slider",
     "default": 50,
     "min": 10,
     "max": 100,
     "unit": "milliseconds"
    }
   ]
  },
  {
   "id": "debounce",
   "title": "Debounce",
   "summary": "Filtering for switches that chatter.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "debounce",
     "title": "Debounce time",
     "summary": "How long the firmware waits for a switch to settle before counting a press. Raise it only if single presses register twice.",
     "type": "slider",
     "default": 5,
     "min": 0,
     "max": 50,
     "unit": "milliseconds"
    }
   ]
  },
  {
   "id": "international",
   "title": "International",
   "summary": "Extra keycodes for non-US input sources. Each pack types correctly only when macOS uses the matching input source.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "belgian",
     "title": "Belgian",
     "summary": "Adds keycodes for the Belgian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "bepo",
     "title": "Bépo",
     "summary": "Adds keycodes for the Bépo input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "brazilian",
     "title": "Brazilian",
     "summary": "Adds keycodes for the Brazilian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "cms",
     "title": "Canadian Multilingual",
     "summary": "Adds keycodes for the Canadian Multilingual input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "croatian",
     "title": "Croatian",
     "summary": "Adds keycodes for the Croatian input source. Pick the same input source in macOS for them to type correctly. On a Mac, pick the Croatian-QWERTZ input source.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "czech",
     "title": "Czech",
     "summary": "Adds keycodes for the Czech input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "danish",
     "title": "Danish",
     "summary": "Adds keycodes for the Danish input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "uk",
     "title": "English (UK)",
     "summary": "Adds keycodes for the English (UK) input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "estonian",
     "title": "Estonian",
     "summary": "Adds keycodes for the Estonian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "french",
     "title": "French",
     "summary": "Adds keycodes for the French input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "frenchca",
     "title": "French (Canada)",
     "summary": "Adds keycodes for the French (Canada) input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "german",
     "title": "German",
     "summary": "Adds keycodes for the German input source. Pick the same input source in macOS for them to type correctly. On a Mac, pick the German Standard input source.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "hungarian",
     "title": "Hungarian",
     "summary": "Adds keycodes for the Hungarian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "icelandic",
     "title": "Icelandic",
     "summary": "Adds keycodes for the Icelandic input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "italian",
     "title": "Italian",
     "summary": "Adds keycodes for the Italian input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "japanese",
     "title": "Japanese",
     "summary": "Adds keycodes for the Japanese input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "kazakh",
     "title": "Kazakh",
     "summary": "Adds keycodes for the Kazakh input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "korean",
     "title": "Korean",
     "summary": "Adds keycodes for the Korean input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "lithuanian",
     "title": "Lithuanian (AZERTY)",
     "summary": "Adds keycodes for the Lithuanian (AZERTY) input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "nordic",
     "title": "Nordic",
     "summary": "Adds keycodes for the Nordic input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "norwegian",
     "title": "Norwegian",
     "summary": "Adds keycodes for the Norwegian input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "polish",
     "title": "Polish (Programmer's)",
     "summary": "Adds keycodes for the Polish (Programmer's) input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "portuguese",
     "title": "Portuguese",
     "summary": "Adds keycodes for the Portuguese input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "portugueseOsx",
     "title": "Portuguese (macOS)",
     "summary": "Adds keycodes for the Portuguese (macOS) input source. Pick the same input source in macOS for them to type correctly. Matches the macOS Portuguese input source.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "romanian",
     "title": "Romanian",
     "summary": "Adds keycodes for the Romanian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "russian",
     "title": "Russian",
     "summary": "Adds keycodes for the Russian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "slovak",
     "title": "Slovak",
     "summary": "Adds keycodes for the Slovak input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "slovenian",
     "title": "Slovenian",
     "summary": "Adds keycodes for the Slovenian input source. Pick the same input source in macOS for them to type correctly. On a Mac, pick the Croatian-PC input source.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "spanish",
     "title": "Spanish",
     "summary": "Adds keycodes for the Spanish input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "spanishla",
     "title": "Spanish (Latin America)",
     "summary": "Adds keycodes for the Spanish (Latin America) input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "swedish",
     "title": "Swedish",
     "summary": "Adds keycodes for the Swedish input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "swissFrench",
     "title": "Swiss French",
     "summary": "Adds keycodes for the Swiss French input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "swissGerman",
     "title": "Swiss German",
     "summary": "Adds keycodes for the Swiss German input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "turkish",
     "title": "Turkish",
     "summary": "Adds keycodes for the Turkish input source. Pick the same input source in macOS for them to type correctly. Intended for Windows and Linux.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "ukranian",
     "title": "Ukrainian",
     "summary": "Adds keycodes for the Ukrainian input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "usint",
     "title": "US International",
     "summary": "Adds keycodes for the US International input source. Pick the same input source in macOS for them to type correctly.",
     "type": "toggle",
     "default": false
    }
   ]
  },
  {
   "id": "misc",
   "title": "Miscellaneous",
   "summary": "Connection, USB and indicator options.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "capsLockStatus",
     "title": "Caps Lock indicator",
     "summary": "Light a status LED while Caps Lock is on.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "disableUsbStartupCheck",
     "title": "Skip USB start-up check",
     "summary": "Start without waiting for the computer to finish configuring USB. Can help KVM switches that fail to detect the board.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "wakeupDelay",
     "title": "Wake-up delay",
     "summary": "Pause, in milliseconds, after the keyboard wakes the computer. Increase it if the board is unresponsive after the Mac wakes.",
     "type": "slider",
     "default": 0,
     "min": 0,
     "max": 500
    },
    {
     "id": "layerLockIdleTimeout",
     "title": "Layer Lock timeout",
     "summary": "Release a locked layer after this many idle seconds. 0 keeps it locked until you unlock it.",
     "type": "slider",
     "default": 0,
     "min": 0,
     "max": 360,
     "unit": "seconds"
    },
    {
     "id": "liveTraining",
     "title": "Live connection",
     "summary": "Lets companion apps read the active layer and key presses over USB. Turning it off saves a little firmware space.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "disableNKRO",
     "title": "Remove N-key rollover",
     "summary": "Compile N-key rollover out and fall back to 6-key rollover. Try this if a computer or firmware setup screen doesn't recognize the board.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "lowPollingRate",
     "title": "Lower USB polling rate",
     "summary": "Poll the computer less often. Typing feels the same; it can fix rare cases where no keystrokes arrive.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "enableDynamicMacros",
     "title": "Dynamic macros",
     "summary": "Allow recording macros on the keyboard itself. Recorded macros are lost when the board restarts.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "enableSpaceCadet",
     "title": "Space Cadet keys",
     "summary": "Add Space Cadet keycodes: tap a Shift, Control or Option key for a parenthesis, hold it for the modifier.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "enableNavigator",
     "title": "Navigator support",
     "summary": "Compile in the Navigator pointing-device module. Listed only for boards that need it switched on.",
     "type": "toggle",
     "default": false,
     "boards": [
      "ergodox-ez-st",
      "halfmoon"
     ]
    }
   ]
  },
  {
   "id": "mouse",
   "title": "Mouse Keys",
   "summary": "How keyboard-driven pointer and scroll keys accelerate.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "mouseInterval",
     "title": "Pointer update interval",
     "summary": "Time between pointer movement steps. Lower values move faster.",
     "type": "slider",
     "default": 20,
     "min": 1,
     "max": 40
    },
    {
     "id": "mouseDelay",
     "title": "Pointer start delay",
     "summary": "Wait after a movement key goes down before the pointer starts. Too low makes small moves hard; too high feels sluggish.",
     "type": "slider",
     "default": 10,
     "min": 0,
     "max": 40
    },
    {
     "id": "mouseMaxSpeed",
     "title": "Pointer top speed",
     "summary": "The fastest the pointer moves while a movement key is held.",
     "type": "slider",
     "default": 10,
     "min": 1,
     "max": 14
    },
    {
     "id": "mouseTimeToMax",
     "title": "Pointer acceleration",
     "summary": "How long the pointer takes to reach top speed.",
     "type": "slider",
     "default": 30,
     "min": 1,
     "max": 120
    },
    {
     "id": "mouseWheelInterval",
     "title": "Scroll interval",
     "summary": "Time between scroll steps. Lower values scroll faster.",
     "type": "slider",
     "default": 80,
     "min": 20,
     "max": 200
    },
    {
     "id": "mouseWheelMaxSpeed",
     "title": "Scroll top speed",
     "summary": "The fastest scrolling gets while a scroll key is held.",
     "type": "slider",
     "default": 8,
     "min": 1,
     "max": 16
    },
    {
     "id": "mouseWheelTimeToMaxSpeed",
     "title": "Scroll acceleration",
     "summary": "How long scrolling takes to reach top speed.",
     "type": "slider",
     "default": 40,
     "min": 1,
     "max": 80
    },
    {
     "id": "mouseWheelDelay",
     "title": "Scroll start delay",
     "summary": "Wait after a scroll key goes down before scrolling starts.",
     "type": "slider",
     "default": 400,
     "min": 0,
     "max": 800,
     "unit": "ms"
    }
   ]
  },
  {
   "id": "rgb",
   "title": "RGB Lighting",
   "summary": "Brightness and hue steps, sleep behavior, and which animations are compiled in.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "rgbHueStep",
     "title": "Hue step",
     "summary": "How far each hue key moves around the color wheel.",
     "type": "slider",
     "default": 8,
     "min": 1,
     "max": 24
    },
    {
     "id": "rgbUsbSuspend",
     "title": "Lights off while asleep",
     "summary": "Turn the LEDs off while the computer sleeps.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "rgbTimeout",
     "title": "Lights off when idle",
     "summary": "Turn the LEDs off after this many idle minutes. 0 keeps them on.",
     "type": "slider",
     "default": 0,
     "min": 0,
     "max": 15,
     "unit": "minutes",
     "requiresPerKeyLighting": true
    },
    {
     "id": "rgbBriStep",
     "title": "Brightness step",
     "summary": "How much each brightness key changes the LED level.",
     "type": "slider",
     "default": 16,
     "min": 1,
     "max": 24
    },
    {
     "id": "disabledAnimations",
     "title": "Animations",
     "summary": "Choose which lighting animations are compiled in. Removing ones you never use frees firmware space.",
     "type": "animation-select",
     "default": [],
     "requiresPerKeyLighting": true,
     "options": [
      {
       "id": "alphaMods",
       "title": "Letters and modifiers"
      },
      {
       "id": "gradientUpDown",
       "title": "Vertical gradient"
      },
      {
       "id": "gradientLeftRight",
       "title": "Horizontal gradient"
      },
      {
       "id": "breathing",
       "title": "Breathing"
      },
      {
       "id": "bandSat",
       "title": "Saturation band"
      },
      {
       "id": "bandHue",
       "title": "Hue band"
      },
      {
       "id": "spinBandSat",
       "title": "Spinning saturation band"
      },
      {
       "id": "spinBandHue",
       "title": "Spinning hue band"
      },
      {
       "id": "spiralSat",
       "title": "Saturation spiral"
      },
      {
       "id": "spiralVal",
       "title": "Brightness spiral"
      },
      {
       "id": "cycleAll",
       "title": "Color cycle"
      },
      {
       "id": "cycleLeftRight",
       "title": "Cycle left to right"
      },
      {
       "id": "cycleUpDown",
       "title": "Cycle top to bottom"
      },
      {
       "id": "rainbowChevron",
       "title": "Rainbow chevron"
      },
      {
       "id": "cycleOutIn",
       "title": "Cycle outside in"
      },
      {
       "id": "cycleOutInDual",
       "title": "Cycle outside in, mirrored"
      },
      {
       "id": "cyclePinwheel",
       "title": "Pinwheel"
      },
      {
       "id": "cycleSpiral",
       "title": "Spiral"
      },
      {
       "id": "dualBeacon",
       "title": "Dual beacon"
      },
      {
       "id": "rainbowBeacon",
       "title": "Rainbow beacon"
      },
      {
       "id": "rainbowPinwheels",
       "title": "Pinwheel per half"
      },
      {
       "id": "flowerBlooming",
       "title": "Blooming"
      },
      {
       "id": "raindrops",
       "title": "Raindrops"
      },
      {
       "id": "jellybeansRaindrops",
       "title": "Jellybean raindrops"
      },
      {
       "id": "hueBreathing",
       "title": "Hue breathing"
      },
      {
       "id": "pendulum",
       "title": "Hue pendulum"
      },
      {
       "id": "wave",
       "title": "Hue wave"
      },
      {
       "id": "pixelFractal",
       "title": "Pixel fractal"
      },
      {
       "id": "pixelFlow",
       "title": "Pixel flow"
      },
      {
       "id": "pixelRain",
       "title": "Pixel rain"
      },
      {
       "id": "typingHeatmap",
       "title": "Typing heatmap"
      },
      {
       "id": "digitalRain",
       "title": "Digital rain"
      },
      {
       "id": "reactiveSimple",
       "title": "Reactive"
      },
      {
       "id": "reactive",
       "title": "Reactive fade"
      },
      {
       "id": "reactiveWide",
       "title": "Reactive wide"
      },
      {
       "id": "reactiveMultiwide",
       "title": "Reactive wide, multi-key"
      },
      {
       "id": "reactiveCross",
       "title": "Reactive cross"
      },
      {
       "id": "reactiveMulticross",
       "title": "Reactive cross, multi-key"
      },
      {
       "id": "reactiveNexus",
       "title": "Reactive nexus"
      },
      {
       "id": "reactiveMultinexus",
       "title": "Reactive nexus, multi-key"
      },
      {
       "id": "reactiveSplash",
       "title": "Splash"
      },
      {
       "id": "reactiveMultisplash",
       "title": "Splash, multi-key"
      },
      {
       "id": "reactiveSolidSplash",
       "title": "Solid splash"
      },
      {
       "id": "reactiveSolidMultisplash",
       "title": "Solid splash, multi-key"
      },
      {
       "id": "starlight",
       "title": "Starlight"
      },
      {
       "id": "starlightDualHue",
       "title": "Starlight, two hues"
      },
      {
       "id": "starlightDualSat",
       "title": "Starlight, two saturations"
      },
      {
       "id": "riverflow",
       "title": "River flow"
      }
     ]
    }
   ]
  },
  {
   "id": "stenography",
   "title": "Stenography",
   "summary": "Keycodes and protocol for steno software.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "stenography",
     "title": "Steno keycodes",
     "summary": "Add stenography keycodes for use with steno software.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "geminipr",
     "title": "GeminiPR protocol",
     "summary": "Send steno chords with GeminiPR instead of the default TX Bolt.",
     "type": "toggle",
     "default": false
    }
   ]
  },
  {
   "id": "tapping",
   "title": "Tapping",
   "summary": "Timing for taps, tap dances and Flow Tap.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "tappingTerm",
     "title": "Tapping term",
     "summary": "How long a dual-function key can be held and still count as a tap. Applies to layer-tap and mod-tap keys.",
     "type": "slider",
     "default": 200,
     "min": 0,
     "max": 1000.0,
     "unit": "milliseconds"
    },
    {
     "id": "tapCodeDelay",
     "title": "Media key delay",
     "summary": "Add a short pause between pressing and releasing media keys. Helps computers that miss them, mostly on Windows.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "dancesTapAction",
     "title": "Prefer tap in tap-and-hold dances",
     "summary": "When you roll quickly over a tap dance that has a hold action, send its tap. Makes fast typing over these keys more forgiving.",
     "type": "toggle",
     "default": true
    },
    {
     "id": "perKeyTappingTerm",
     "title": "Per-key tapping term",
     "summary": "Allow a different tapping term on individual keys, for fingers that are faster or slower than the rest.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "flowTap",
     "title": "Flow Tap",
     "summary": "Right after another key, treat dual-function keys as taps for this long. Prevents accidental holds while typing quickly, which matters most for home-row modifiers.",
     "type": "slider",
     "default": 100,
     "min": 1,
     "max": 1000.0,
     "toggleable": true
    }
   ]
  },
  {
   "id": "tapping-dual",
   "title": "Dual-Function Keys",
   "summary": "How keys with both a tap and a hold action decide which one you meant.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "retroTapping",
     "title": "Retro tapping",
     "summary": "If a dual-function key is held past the tapping term and released with nothing else pressed, send its tap anyway.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "permissiveHold",
     "title": "Permissive hold",
     "summary": "Choose the hold action when another key is pressed and released while the dual-function key is still down, even inside the tapping term.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "holdOnOtherKeyPress",
     "title": "Hold on other key press",
     "summary": "Choose the hold action as soon as any other key goes down. More eager than permissive hold; suits fast typists and long tapping terms.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "tappingForceHold",
     "title": "Hold after quick tap",
     "summary": "Holding a dual-function key straight after tapping it gives the hold action instead of repeating the tap.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "legacyDualFunctionDances",
     "title": "Legacy dual-function keys",
     "summary": "Build two-function keys as tap dances, like older layouts. They feel less responsive; use this only to keep old behavior.",
     "type": "toggle",
     "default": false
    }
   ]
  },
  {
   "id": "oneshot",
   "title": "One-Shot Keys",
   "summary": "Behavior of one-shot modifiers and one-shot layers.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "oneShotTapToggle",
     "title": "Taps to lock a one-shot",
     "summary": "Number of taps that lock a one-shot modifier or layer on until it is tapped again.",
     "type": "slider",
     "default": null,
     "min": 2,
     "max": 5,
     "toggleable": true
    },
    {
     "id": "oneShotTimeout",
     "title": "One-shot timeout",
     "summary": "Clear a pending one-shot modifier or layer after this long.",
     "type": "slider",
     "default": null,
     "min": 100,
     "max": 8000.0,
     "unit": "milliseconds",
     "toggleable": true
    }
   ]
  },
  {
   "id": "holding",
   "title": "Holding",
   "summary": "Layer keys and chordal hold.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "ambidexLT",
     "title": "Unblock layer keys on their own layer",
     "summary": "The key you hold to reach a layer is normally blocked on that layer. Turn this on to give it an action there; you need a second key to reach the layer and tap it.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "chordalHold",
     "title": "Chordal hold",
     "summary": "When a dual-function key and a key on the same hand go down within the tapping term, treat the first as a tap. Cuts accidental modifiers with home-row mods.",
     "type": "toggle",
     "default": false
    },
    {
     "id": "chordalHoldExcludeThumbs",
     "title": "Exclude thumbs from chordal hold",
     "summary": "Let thumb keys choose tap or hold freely, whichever hand the next key is on.",
     "type": "toggle",
     "default": false,
     "boards": [
      "ergodox-ez",
      "ergodox-ez-st",
      "moonlander",
      "halfmoon",
      "voyager"
     ]
    }
   ]
  },
  {
   "id": "navigator",
   "title": "Navigator",
   "summary": "The Navigator module, the half it is on, and its trackball or trackpad options.",
   "visibleOnVoyager": true,
   "settings": [
    {
     "id": "sensitivity",
     "title": "Trackball sensitivity",
     "summary": "How far the pointer moves as the ball turns. Higher is faster.",
     "type": "slider",
     "default": 40,
     "min": 5,
     "max": 125,
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "automouseThreshold",
     "title": "Auto-mouse sensitivity",
     "summary": "How much movement switches to the auto-mouse layer. Lower values react to smaller movements.",
     "type": "slider",
     "default": 10,
     "min": 0,
     "max": 100,
     "navigatorKinds": [
      "trackball",
      "trackpad"
     ]
    },
    {
     "id": "automouseTime",
     "title": "Auto-mouse release delay",
     "summary": "How long after movement stops the auto-mouse layer turns off.",
     "type": "slider",
     "default": 650,
     "min": 1,
     "max": 5000.0,
     "unit": "milliseconds",
     "navigatorKinds": [
      "trackball",
      "trackpad"
     ]
    },
    {
     "id": "invertScrollX",
     "title": "Invert horizontal scrolling",
     "summary": "Reverse horizontal scrolling and drag scrolling.",
     "type": "toggle",
     "default": false,
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "invertScrollY",
     "title": "Invert vertical scrolling",
     "summary": "Reverse vertical scrolling and drag scrolling.",
     "type": "toggle",
     "default": false,
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "oneShotAutoMouse",
     "title": "Leave auto-mouse on key press",
     "summary": "Keep the auto-mouse layer until a key is pressed, then start the release delay. Pair it with a short delay.",
     "type": "toggle",
     "default": false,
     "navigatorKinds": [
      "trackball",
      "trackpad"
     ]
    },
    {
     "id": "oneShotAutoMouseTimeout",
     "title": "Auto-mouse idle timeout",
     "summary": "With the option above on, also leave the auto-mouse layer after this many idle seconds.",
     "type": "slider",
     "default": 10,
     "min": 1,
     "max": 15,
     "unit": "seconds",
     "toggleable": true,
     "navigatorKinds": [
      "trackball",
      "trackpad"
     ],
     "dependsOn": {
      "key": "oneShotAutoMouse",
      "value": true
     }
    },
    {
     "id": "scrollOnly",
     "title": "Scroll only",
     "summary": "Use the trackball only for scrolling; the pointer stays put.",
     "type": "toggle",
     "default": false,
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "rotation",
     "title": "Rotation",
     "summary": "Rotate the sensor's axes to match how the Navigator is mounted.",
     "type": "slider",
     "default": 0,
     "min": -180,
     "max": 180,
     "unit": "degrees",
     "navigatorKinds": [
      "trackball",
      "trackpad"
     ]
    },
    {
     "id": "aimSpeed",
     "title": "Aim speed",
     "summary": "Pointer speed in aim mode, for precise moves.",
     "type": "slider",
     "default": 1,
     "min": 0,
     "max": 2,
     "navigatorKinds": [
      "trackball"
     ],
     "marks": {
      "0": "Slow",
      "1": "Normal",
      "2": "Fast"
     }
    },
    {
     "id": "turboSpeed",
     "title": "Turbo speed",
     "summary": "Pointer speed in turbo mode, for crossing the screen quickly.",
     "type": "slider",
     "default": 1,
     "min": 0,
     "max": 2,
     "navigatorKinds": [
      "trackball"
     ],
     "marks": {
      "0": "Slow",
      "1": "Normal",
      "2": "Fast"
     }
    },
    {
     "id": "aimLayers",
     "title": "Aim layers",
     "summary": "Layers that put the trackball in aim mode.",
     "type": "layer-select",
     "default": [],
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "turboLayers",
     "title": "Turbo layers",
     "summary": "Layers that put the trackball in turbo mode.",
     "type": "layer-select",
     "default": [],
     "navigatorKinds": [
      "trackball"
     ]
    },
    {
     "id": "dragScrollLayers",
     "title": "Drag-scroll layers",
     "summary": "Layers on which moving the trackball scrolls instead of pointing.",
     "type": "layer-select",
     "default": [],
     "navigatorKinds": [
      "trackball"
     ]
    }
   ]
  }
 ]
}
"""#
}
