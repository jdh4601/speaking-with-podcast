(function(root){
const METRICS=[
 {key:'mistakesPer100',label:'100단어당 실수',lowerIsBetter:true,unit:'건'},
 {key:'disfluencyPer100',label:'100단어당 말 더듬·재시작',lowerIsBetter:true,unit:'회'},
 {key:'wordsPerTurn',label:'한 번에 이어 말한 단어',lowerIsBetter:false,unit:'단어'},
 {key:'talkShare',label:'내 발화 비율',lowerIsBetter:false,unit:'%'},
];

function highlightParts(sentence,target){
 const start=target?sentence.indexOf(target):-1;
 if(start<0)return[{text:sentence,marked:false}];
 const end=start+target.length;
 return[
  {text:sentence.slice(0,start),marked:false},
  {text:target,marked:true},
  {text:sentence.slice(end),marked:false},
 ].filter(part=>part.text);
}

function addCount(counts,key){counts.set(key,(counts.get(key)||0)+1)}

function reviewQueue(sessions,mastered){
 const categoryTotals=new Map(),patternTotals=new Map(),latest=new Map();
 for(const session of sessions)for(const mistake of session.mistakes){
  addCount(categoryTotals,mistake.category);
  addCount(patternTotals,mistake.pattern);
  // Sessions arrive oldest first, so the last write is the newest example.
  latest.set(mistake.pattern,{...mistake,latestDate:session.date});
 }
 return[...latest.values()]
  .filter(card=>!mastered[card.pattern]||card.latestDate>mastered[card.pattern])
  .map(card=>({...card,categoryTotal:categoryTotals.get(card.category),patternTotal:patternTotals.get(card.pattern)}))
  .sort((a,b)=>b.categoryTotal-a.categoryTotal||b.latestDate.localeCompare(a.latestDate));
}

function direction(metric,delta,previous){
 if(previous===undefined)return'baseline';
 if(delta===0)return'same';
 return(delta<0)===metric.lowerIsBetter?'better':'worse';
}

function metricTrend(sessions){
 return METRICS.map(metric=>{
  const values=sessions.map(session=>session.metrics[metric.key]).filter(Number.isFinite);
  const latest=values.at(-1),previous=values.at(-2);
  const delta=previous===undefined?0:Math.round((latest-previous)*10)/10;
  return{key:metric.key,label:metric.label,unit:metric.unit,values,latest,delta,direction:direction(metric,delta,previous)};
 });
}

const api={METRICS,highlightParts,reviewQueue,metricTrend};
if(typeof module==='object'&&module.exports)module.exports=api;else root.ConversationCore=api;
})(this);
