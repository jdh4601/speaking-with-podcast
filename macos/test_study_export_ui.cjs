const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const source=fs.readFileSync('macos/web/study-export.js','utf8');
function setup(fetcher){
 class Element{
  constructor(){this.disabled=false;this.hidden=false;this.checked=true;this.textContent='';this.value='';this.listeners={};this.children=[];this.classList={toggle(){}};this.nodes={};}
  set innerHTML(value){this.html=value;for(const id of [...value.matchAll(/id="([^"]+)"/g)].map(m=>m[1]))this.nodes['#'+id]=new Element();this.nodes['#pack-warnings'].nodes={summary:new Element(),ul:new Element()};}
  get innerHTML(){return this.html||'';}
  querySelector(key){return this.nodes[key];}setAttribute(){}removeAttribute(){}
  replaceChildren(){this.children=[];}append(x){this.children.push(x);}after(x){this.afterNode=x;}
  closest(){return review;}addEventListener(name,fn){this.listeners[name]=fn;}remove(){}click(){}
 }
 const review=new Element(),select=new Element();select.value='a';select.title='Episode A';Object.defineProperty(select,'selectedOptions',{get(){return [{textContent:select.title}]}});
 const form=[new Element(),new Element()],window={listeners:{},addEventListener(name,fn){this.listeners[name]=fn;}};
 const context=vm.createContext({document:{querySelector(){return select},createElement(){return new Element()},querySelectorAll(){return form},body:new Element()},window,busy:false,MutationObserver:class{observe(){}},fetch:fetcher,AbortController,URL,setTimeout,clearTimeout,Promise,console});
 vm.runInContext(source,context);
 return {context,select,window,controls:review.afterNode,get(id){return review.afterNode.querySelector(id)}};
}
const result={exportId:'export-a',episodeId:'a',filename:'a.podstudy',downloadUrl:'/api/exports/a.podstudy',cardCount:2,audioCount:1,bytes:1024,warnings:['2번 표현: <img onerror=bad()> 음성 없음']};
function response(value){return {ok:true,async json(){return value}};}
(async()=>{
 let calls=[];
 let app=setup(async path=>{calls.push(path);return response(path==='/api/export'?{job:'j1'}:{status:'done',result});});
 await app.get('#pack-export').onclick();
 assert.equal(app.get('#pack-save').hidden,false);assert.equal(app.context.busy,false);
 const warning=app.get('#pack-warnings').querySelector('ul').children[0];assert.match(warning.textContent,/<img/);assert.equal(warning.innerHTML,'');
 assert.match(app.get('#pack-status').textContent,/Episode A/);
 app.window.webkit={messageHandlers:{saveStudyPack:{postMessage(){}}}};
 await app.get('#pack-save').onclick();assert.equal(app.get('#pack-save').disabled,true);
 app.window.listeners['study-pack-saved']({detail:{state:'cancelled'}});
 assert.equal(app.get('#pack-save').disabled,false);assert.equal(app.get('#pack-save').hidden,false);assert.match(app.get('#pack-status').textContent,/다시 저장/);
 console.log('PASS selected title, counts, safe per-card warnings, cancelled native save retry');

 let app2;app2=setup(async path=>{if(path==='/api/export')return response({job:'j2'});app2.select.value='b';app2.select.title='Episode B';return response({status:'done',result});});
 await app2.get('#pack-export').onclick();assert.equal(app2.get('#pack-save').hidden,true);assert.match(app2.get('#pack-status').textContent,/바뀌었습니다/);
 console.log('PASS selected episode change discards stale result');

 let exports=0,fail=true;const app3=setup(async path=>{if(path==='/api/export'){exports++;return response({job:'j3'});}if(fail){fail=false;throw Error('network disconnected');}return response({status:'done',result});});
 await app3.get('#pack-export').onclick();assert.match(app3.get('#pack-export').textContent,/진행 상황 다시 확인/);assert.equal(app3.context.busy,false);
 await app3.get('#pack-export').onclick();assert.equal(exports,1);assert.equal(app3.get('#pack-save').hidden,false);
 console.log('PASS interrupted polling resumes the same server job');
})();
