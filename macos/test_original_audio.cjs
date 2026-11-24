const assert = require('node:assert/strict');
const {setImmediate: tick} = require('node:timers/promises');
global.window = {addEventListener() {}};
const requested = [];
const clips = [];
const played = [];
let releaseFirst;
const gate = new Promise(resolve => {releaseFirst = resolve});
global.fetch = async (path, options) => {
  if (path === '/api/audio') {
    const {index} = JSON.parse(options.body);
    requested.push(index);
    return {ok: true, json: () => ({job: index})};
  }
  if (path.startsWith('/api/jobs/')) {
    const index = Number(path.split('/').pop());
    if (index === 0) await gate;
    return {ok: true, json: () => ({status: 'done', result: {
      clipUrl: '/clip/' + index, start: index, duration: 1
    }})};
  }
  clips.push(path);
  return {ok: true, blob: () => new Blob([path])};
};
global.Audio = class {
  pause() {this.paused=true;this.onpause?.()}
  play() {this.paused=false;played.push(this);this.onplay?.()}
};
require('./web/original-audio.js');
(async () => {
  const audio = window.OriginalAudio;
  const session = {id: 'episode', expressions: Array(6)};
  audio.preload(session, 0);
  const stale = audio.play(session, 0);
  audio.stop();
  audio.preload(session, 3);
  releaseFirst();
  await stale;
  await tick();
  assert.deepEqual(requested, [0, 3, 4]);
  assert.equal(played.length, 0);
  for (const index of [3, 4, 3]) await audio.play(session, index);
  assert.equal(played.length, 3);
  assert.deepEqual(clips, ['/clip/0', '/clip/3', '/clip/4']);
  assert.deepEqual(requested, [0, 3, 4]);
  const updates = [];
  const progress = (...state) => updates.push(state);
  const toggle = () => audio.toggle(session, 3, () => {}, progress);
  await toggle();
  const player = played.at(-1);
  player.currentTime = 0.4;
  player.ontimeupdate();
  assert.deepEqual(updates.at(-1), [0.4, true, 1]);
  await toggle();
  assert.deepEqual(updates.at(-1), [0.4, false, 1]);
  await toggle();
  assert.equal(played.at(-1), player);
  assert.deepEqual(updates.at(-1), [0.4, true, 1]);
  player.ended = true;
  player.onended();
  assert.deepEqual(updates.at(-1), [1, false, 1]);
  audio.stop();
  player.ontimeupdate();
  assert.deepEqual(updates.at(-1), [0, false]);
  console.log('PASS preloaded playback, repeat, stale navigation and shared preparation');
})().catch(error => {console.error(error); process.exitCode = 1});
