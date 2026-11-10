(function(){
const SVG_NS='http://www.w3.org/2000/svg';

function svgNode(tag,attributes){
 const node=document.createElementNS(SVG_NS,tag);
 for(const [name,value] of Object.entries(attributes))node.setAttribute(name,value);
 return node;
}

function chart(metric,width=200){
 const height=56,padding=8,horizontalPadding=Math.max(padding,width*.02),{samples,values}=metric;
 const svg=svgNode('svg',{
  class:'trend-chart',viewBox:`0 0 ${width} ${height}`,preserveAspectRatio:'none',role:'img',
  'aria-label':`${metric.label} · ${samples.map(({date,value})=>`${date} ${value}${metric.unit}`).join(', ')}`,
 });
 const low=Math.min(...values),high=Math.max(...values);
 const points=samples.map(({date,value},index)=>({
  date,value,
  x:samples.length>1?horizontalPadding+index*(width-2*horizontalPadding)/(samples.length-1):width/2,
  y:high===low?height/2:height-padding-(value-low)/(high-low)*(height-2*padding),
 }));
 if(points.length>1){
  let path=`M ${points[0].x} ${points[0].y}`;
  for(let index=1;index<points.length;index++){
   const previous=points[index-1],current=points[index];
   // Horizontal tangents keep each curve within the two measured values.
   const middle=(previous.x+current.x)/2;
   path+=` C ${middle} ${previous.y} ${middle} ${current.y} ${current.x} ${current.y}`;
  }
  svg.append(svgNode('path',{class:'trend-line',d:path}));
 }
 for(const {date,value,x,y} of points){
  const mark=svgNode('path',{class:'trend-point',d:`M ${x} ${y} h 0`});
  const hit=svgNode('circle',{class:'trend-hit',cx:x,cy:y,r:10});
  const tip=svgNode('title',{});
  tip.textContent=`${date}: ${value}${metric.unit}`;
  hit.append(tip);
  svg.append(mark,hit);
 }
 return svg;
}

window.ConversationTrend={chart};
})();
