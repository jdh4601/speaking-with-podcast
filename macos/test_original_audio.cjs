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
  pause() {}
  play() {played.push(this)}
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
  audio.stop();
  console.log('PASS preloaded playback, repeat, stale navigation and shared preparation');
})().catch(error => {console.error(error); process.exitCode = 1});
