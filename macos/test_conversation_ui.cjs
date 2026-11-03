const assert=require('node:assert/strict');
const {highlightParts,reviewQueue,metricTrend,lessonPriorities}=require('./web/conversation-core.js');

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

const labelled=(category,sentence)=>({...mistake(category,'p'),sentence});
const lesson=session('2026-11-03',[labelled('관사','a1'),labelled('시제','t1'),labelled('시제','t2'),labelled('수일치','n1'),labelled('전치사','o1'),labelled('시제','t3'),labelled('관사','a2')]);
const priorities=lessonPriorities([session('2026-10-27',[labelled('기타','old')]),lesson]);
assert.equal(priorities.date,'2026-11-03');
assert.deepEqual(priorities.items.map(item=>[item.category,item.count]),[['시제',3],['관사',2],['수일치',1],['전치사',1]]);
const nineCategories=session('2026-11-03',['a','b','c','d','e','f','g','h','i'].map(name=>labelled(name,'s')));
assert.equal(lessonPriorities([nineCategories]).items.length,7);
assert.equal(priorities.items[0].example.sentence,'t1');
assert.deepEqual(lessonPriorities([]),{date:null,items:[]});
assert.deepEqual(lessonPriorities([session('2026-11-03',[])]),{date:'2026-11-03',items:[]});

const fs=require('node:fs'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'web/index.html'),'utf8');
for(const removed of ['class="stats"','class="calendar"','class="roadmap"','id="week"','id="topic"','id="daily-note"','id="topic-dialog"','id="today-strip"'])
 assert.equal(html.includes(removed),false,removed);
for(const required of ['id="mistake-review"','id="week-routine"','id="mistake-summary"','id="mistake-start"','id="mistake-stop"','href="conversation.html"','id="settings-open"','id="today-review"','conversation-core.js','mistake-review.js'])
 assert.equal(html.includes(required),true,required);
const app=fs.readFileSync(path.join(__dirname,'web/app.js'),'utf8');
for(const id of [...app.matchAll(/\$\('#([a-z-]+)'\)/g)].map(match=>match[1]))
 assert.equal(html.includes(`id="${id}"`),true,`app.js targets missing #${id}`);
