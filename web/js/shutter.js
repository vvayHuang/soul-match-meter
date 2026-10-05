// The shutter click on a locked reading. Ported from
// soul-match-meter/Model/ShutterSound.swift: 70 ms of white noise with a cubic
// decay through an 1800 Hz high-pass, at half gain.
//
// Browsers only let a page make sound after a touch, so `prime` is called
// when the hold starts and `play` when it locks.

let context = null;
let noise = null;

export function prime() {
  try {
    context ??= new (window.AudioContext ?? window.webkitAudioContext)();
    if (context.state === 'suspended') context.resume();
  } catch {
    // No audio here; the reading locks silently.
    context = null;
  }
}

export function play() {
  prime();
  if (!context) return;
  try {
    if (!noise) {
      const count = Math.floor(context.sampleRate * 0.07);
      noise = context.createBuffer(1, count, context.sampleRate);
      const samples = noise.getChannelData(0);
      for (let i = 0; i < count; i++) {
        samples[i] = (Math.random() * 2 - 1) * (1 - i / count) ** 3;
      }
    }
    const source = context.createBufferSource();
    source.buffer = noise;
    const highPass = context.createBiquadFilter();
    highPass.type = 'highpass';
    highPass.frequency.value = 1800;
    highPass.Q.value = 1;
    const gain = context.createGain();
    gain.gain.value = 0.5;
    source.connect(highPass).connect(gain).connect(context.destination);
    source.start();
  } catch {
    // Carry on without the click.
  }
}
