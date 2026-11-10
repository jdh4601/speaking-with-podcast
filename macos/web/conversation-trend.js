(function(){
const SVG_NS='http://www.w3.org/2000/svg';

function svgNode(tag,attributes){
 const node=document.createElementNS(SVG_NS,tag);
 for(const [name,value] of Object.entries(attributes))node.setAttribute(name,value);
 return node;
}

function chart(metric,{showValues=false}={}){
 const {samples,values}=metric;
 const width=200,height=56;
 const horizontalPadding=showValues?width/(2*samples.length):8;
 const topPadding=showValues?16:8,bottomPadding=showValues?13:8;
 const svg=svgNode('svg',{
  class:'trend-chart',viewBox:`0 0 ${width} ${height}`,preserveAspectRatio:'none',role:'img',
  'aria-label':`${metric.label} · ${samples.map(({date,value})=>`${date} ${value}${metric.unit}`).join(', ')}`,
 });
 const low=Math.min(...values),high=Math.max(...values);
 const points=samples.map(({date,value},index)=>({
  date,value,
  x:samples.length>1?horizontalPadding+index*(width-2*horizontalPadding)/(samples.length-1):width/2,
  y:high===low?height/2:height-bottomPadding-(value-low)/(high-low)*(height-topPadding-bottomPadding),
 }));
 if(points.length>1){
  svg.append(svgNode('polyline',{
   class:'trend-line',points:points.map(({x,y})=>`${x},${y}`).join(' '),
  }));
 }
 for(const {date,value,x,y} of points){
  const mark=svgNode('path',{class:'trend-point',d:`M ${x} ${y} h 0`});
  const hit=svgNode('circle',{class:'trend-hit',cx:x,cy:y,r:10});
  const tip=svgNode('title',{});
  tip.textContent=`${date}: ${value}${metric.unit}`;
  hit.append(tip);
  svg.append(mark,hit);
 }
 if(!showValues)return svg;

 const plot=document.createElement('div');
 plot.className='trend-labelled-plot';
 plot.style.minWidth=`${samples.length*68}px`;
 plot.append(svg);
 for(const {date,value,x,y} of points){
  const number=document.createElement('span');
  number.className='trend-point-value';
  number.textContent=`${value}${metric.unit}`;
  number.style.left=`${x/width*100}%`;
  number.style.top=`${y/height*100}%`;
  number.setAttribute('aria-hidden','true');

  const dateLabel=document.createElement('time');
  dateLabel.className='trend-point-date';
  dateLabel.dateTime=date;
  dateLabel.textContent=date;
  dateLabel.style.left=number.style.left;
  dateLabel.setAttribute('aria-hidden','true');
  plot.append(number,dateLabel);
 }
 return plot;
}

window.ConversationTrend={chart};
})();
