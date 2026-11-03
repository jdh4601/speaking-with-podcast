const assert=require('node:assert/strict');
const {highlightParts,reviewQueue,metricTrend}=require('./web/conversation-core.js');

const mistake=(category,pattern)=>({category,pattern,sentence:'s',wrong:'w',corrected:'c',translation:'t',rule:'r'});
const session=(date,mistakes)=>({date,mistakes,metrics:{}});
const withMetrics=metrics=>({date:'2026-11-03',mistakes:[],metrics});
const byKey=(trend,key)=>trend.find(item=>item.key===key);

assert.deepEqual(highlightParts('I go home','go'),
 [{text:'I ',marked:false},{text:'go',marked:true},{text:' home',marked:false}]);
assert.deepEqual(highlightParts('<img src=x>','<img'),
 [{text:'<img',marked:true},{text:' src=x>',marked:false}]);
assert.deepEqual(highlightParts('abc','zzz'),[{text:'abc',marked:false}]);

const article=mistake('관사','the same'),tense=mistake('시제','past tense');
const sessions=[session('2026-11-01',[article,tense]),session('2026-11-03',[article])];
const queue=reviewQueue(sessions,{});
assert.equal(queue.length,2);
assert.equal(queue[0].pattern,'the same');
assert.equal(queue[0].latestDate,'2026-11-03');
assert.equal(queue[0].patternTotal,2);
assert.equal(queue[0].categoryTotal,2);
assert.equal(reviewQueue([session('2026-11-01',[article])],{'the same':'2026-11-01'}).length,0);
assert.equal(reviewQueue([session('2026-11-03',[article])],{'the same':'2026-11-01'}).length,1);
assert.deepEqual(reviewQueue([session('2026-11-01',[])],{}),[]);

const improved=metricTrend([withMetrics({mistakesPer100:5}),withMetrics({mistakesPer100:4})]);
assert.equal(byKey(improved,'mistakesPer100').direction,'better');
assert.equal(byKey(improved,'mistakesPer100').delta,-1);
assert.equal(byKey(metricTrend([withMetrics({mistakesPer100:5})]),'mistakesPer100').direction,'baseline');
assert.equal(byKey(metricTrend([withMetrics({mistakesPer100:4}),withMetrics({mistakesPer100:5})]),'mistakesPer100').direction,'worse');
assert.equal(byKey(metricTrend([withMetrics({wordsPerTurn:8}),withMetrics({wordsPerTurn:8})]),'wordsPerTurn').direction,'same');
assert.equal(byKey(metricTrend([withMetrics({wordsPerTurn:8}),withMetrics({wordsPerTurn:9})]),'wordsPerTurn').direction,'better');
assert.deepEqual(metricTrend([]).map(item=>item.values.length),[0,0,0,0]);

const fs=require('node:fs'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'web/index.html'),'utf8');
for(const removed of ['class="stats"','class="calendar"','class="roadmap"','id="week"','id="topic"','id="daily-note"','id="topic-dialog"'])
 assert.equal(html.includes(removed),false,removed);
for(const required of ['id="mistake-review"','id="today-strip"','href="conversation.html"','id="settings-open"','id="today-review"','conversation-core.js','mistake-review.js'])
 assert.equal(html.includes(required),true,required);
const app=fs.readFileSync(path.join(__dirname,'web/app.js'),'utf8');
for(const id of [...app.matchAll(/\$\('#([a-z-]+)'\)/g)].map(match=>match[1]))
 assert.equal(html.includes(`id="${id}"`),true,`app.js targets missing #${id}`);
