'use strict';
const fs=require('fs'), vm=require('vm');
const source=fs.readFileSync(process.argv[2],'utf8');
const a=source.indexOf('function cacheCard(root,st){'),b=source.indexOf('function renderNetwork(root,st){',a);
if(a<0||b<0)throw Error('cache form missing');
const inputs=[],selects=[],buttons=[];let request,feedback;
const ctx={
  state:{busy:false,busySetting:''},
  E:(tag,attrs,children)=>{const e={tag,attrs,children,value:attrs&&attrs.value};if(tag==='input')inputs.push(e);if(tag==='select')selects.push(e);return e;},
  btn:(label,style,click,attrs)=>{const e={label,click,attrs};buttons.push(e);return e;},
  settingFeedback:()=>null,setSettingFeedback:(key,msg,type)=>{feedback={key,msg,type};},
  renderNetwork:()=>{},callSetCache:(size,ttl)=>{request=[size,ttl];return Promise.resolve({ok:true,job:'action'});},
  awaitSettingResult:()=>Promise.resolve({ok:true}),refresh:()=>Promise.resolve(),withRpcError:(s,e)=>s+e,
};
vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);
ctx.cacheCard({}, {cache_total:1200,cache_ttl:0});
if(inputs.length!==1||inputs[0].value!=='1200'||selects[0].value!=='0'||selects[0].children.map(o=>o.attrs.value).join(',')!=='0,300,900,1800')throw Error('cache form defaults incorrect');
inputs[0].value='1600';selects[0].value='900';buttons[0].click();
setTimeout(()=>{
  if(!request||request.join(',')!=='1600,900'||feedback.type!=='ok'||ctx.state.busy)throw Error('cache apply did not complete');
  request=null;inputs.length=0;selects.length=0;buttons.length=0;ctx.cacheCard({}, {cache_total:0,cache_ttl:37});
  if(selects[0].value!=='37'||!selects[0].children.some(o=>o.attrs.value==='37'))throw Error('existing TTL was lost');
  selects[0].value='3601';buttons[0].click();
  if(request||feedback.type!=='error')throw Error('invalid TTL was accepted');
},20);
