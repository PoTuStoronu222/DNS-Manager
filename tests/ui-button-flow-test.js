'use strict';
const fs=require('fs'), vm=require('vm');
const source=fs.readFileSync(process.argv[2],'utf8');
function extract(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);if(a<0||b<0)throw Error('missing '+start);return source.slice(a,b);}
const delay=()=>new Promise(resolve=>setTimeout(resolve,20));
async function testCurrent(result,expected){
  const st={doh_instances:[{id:'dns1',slot:'1',status:'OK'}]};
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:st},render:()=>{},setAction:()=>{},checkKey:id=>id,callTestCurrent:()=>Promise.resolve({ok:true,job:'j'}),pollJob:(root,job,meta,done)=>done(st,result)};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
  ctx.testCurrent({});await delay();
  if(ctx.state.currentTest.status!==expected)throw Error('current DNS result: '+JSON.stringify(ctx.state.currentTest));
}
async function testSingleError(){
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:{}},render:()=>{},refresh:()=>Promise.resolve(),setAction:()=>{},withRpcError:(s,e)=>s+' '+e.message,callTestOne:()=>Promise.reject(Error('timeout'))};
  vm.createContext(ctx);vm.runInContext(extract('function testOne(id,root,origin,done){','function testCurrent(root){'),ctx);
  ctx.testOne('dns1',{},'catalog');await delay();
  if(ctx.state.jobRunning||!String(ctx.state.pageNotice.catalog).includes('timeout'))throw Error('single DNS error hidden');
}
async function testUpdateErrors(){
  let notice='',kind='',reloaded=false;
  const ctx={state:{updatingAll:false,busy:false},window:{},location:{reload:()=>{reloaded=true;}},setTimeout:(f)=>setTimeout(f,0),renderOverview:()=>{},refresh:()=>Promise.resolve(),globalUpdateNotice:(m,k)=>{notice=m;kind=k;},withRpcError:(m,e)=>m+String(e),callManagerUpdate:()=>Promise.resolve({ok:false,error:'не удалось проверить актуальность'}),callHdpUpdate:()=>Promise.resolve({ok:true,updated:false,message:'уже актуален'}),callUpdateCatalog:()=>Promise.resolve({ok:true,updated:false,message:'уже актуален'}),callUpdate:()=>Promise.resolve({ok:true,updated:true})};
  vm.createContext(ctx);vm.runInContext(extract('function updateAll(root){','function uninstallManager(root){'),ctx);
  await ctx.updateAll({});await delay();
  if(kind!=='error'||reloaded||!notice.includes('не удалось'))throw Error('update failure hidden: '+kind+' '+notice);
}
async function testUpdateTimeout(){
  let otherCalls=0,kind='',notice='';
  const ctx={state:{updatingAll:false,busy:false},window:{},location:{reload:()=>{}},setTimeout,renderOverview:()=>{},refresh:()=>Promise.resolve(),globalUpdateNotice:(m,k)=>{notice=m;kind=k;},withRpcError:(m,e)=>m+' '+e.message,callManagerUpdate:()=>Promise.reject(Error('timeout')),callHdpUpdate:()=>{otherCalls++;return Promise.resolve({ok:true});},callUpdateCatalog:()=>{otherCalls++;return Promise.resolve({ok:true});},callUpdate:()=>{otherCalls++;return Promise.resolve({ok:true});}};
  vm.createContext(ctx);vm.runInContext(extract('function updateAll(root){','function uninstallManager(root){'),ctx);
  await ctx.updateAll({});
  if(otherCalls!==0||kind!=='error'||!notice.includes('неизвестен'))throw Error('continued after uncertain update');
}
async function testProfileStatus(){
  const st={regional_mode:'isp',slots:[]};let dohCalls=0,rendered=null;
  const ctx={state:{busy:true,jobRunning:true,checking:{},pageNotice:{},profileProgress:{}},window:{dmState:{}},setAction:()=>{},profileName:x=>x,stripAnsi:x=>x,profileProgressUpdate:()=>{},renderProfiles:()=>{},currentRoute:()=> 'doh',callJob:()=>Promise.resolve({status:'done',result:'ok'}),callDohStatus:()=>{dohCalls++;return Promise.resolve(st);},callStatus:()=>{throw Error('wrong status route');},render:(root,s)=>{rendered=s;},setTimeout};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob({},'profile',{mode:'profile',profile:'clean'});await delay();
  if(dohCalls!==1||!rendered||rendered.regional_mode!=='isp')throw Error('regional mode lost after profile apply');
}
async function testSlotDraft(){
  const ctx={state:{busy:false,pageNotice:{}},window:{dmState:{}},slotLabel:x=>'DNS '+x,renderSlots:()=>{},refresh:()=>Promise.resolve(),setAction:()=>{},withRpcError:(s,e)=>s+e.message,awaitSettingResult:r=>Promise.resolve(r),callSlotDomains:()=>Promise.resolve({ok:false,error:'bad domain'})};
  vm.createContext(ctx);vm.runInContext(extract('function saveSlotDomains(slot,input,root){','function refreshDeviceDnsPanels(root){'),ctx);
  ctx.saveSlotDomains('1',{value:'bad domain'},{});await delay();
  if(ctx.state.slotDomainDrafts['1']!=='bad domain'||ctx.state.pageNotice.slots!=='bad domain')throw Error('domain draft or error lost');
  ctx.callSlotDomains=()=>Promise.resolve({ok:true});ctx.saveSlotDomains('1',{value:'example.com'},{});await delay();
  if(Object.prototype.hasOwnProperty.call(ctx.state.slotDomainDrafts,'1'))throw Error('saved domain draft was not cleared');
}
async function testDeviceSave(){
  let renders=[];
  const ctx={state:{busy:false,jobRunning:false,pageNotice:{}},window:{dmState:{},dmLanDevices:{}},renderDeviceDns:()=>renders.push(ctx.state.busy),setAction:()=>{},withRpcError:(s,e)=>s+e.message,awaitSettingResult:r=>Promise.resolve(r),callSetDeviceDns:()=>Promise.resolve({ok:true}),callLanDevices:()=>Promise.resolve({ok:true,devices:[]})};
  vm.createContext(ctx);vm.runInContext(extract('function refreshDeviceDnsPanels(root){','function slotOptionsForCatalog(cat){'),ctx);
  ctx.saveDeviceDns('aa:bb:cc:dd:ee:ff',{querySelectorAll:()=>[{checked:true,value:'1',getAttribute:()=> '1'}]},{});await delay();
  if(renders[0]!==true||ctx.state.busy||!ctx.state.pageNotice.slots.includes('сохранены'))throw Error('device save state missing');
}
async function testCatalogError(){
  const ctx={state:{catalogLoading:false,category:'all',offset:0,limit:18,pageNotice:{}},window:{dmCatalog:{servers:[{id:'stale'}]}},callCatalog:()=>Promise.resolve({ok:false,error:'failed'}),renderCatalog:()=>{},renderCatalogBody:()=>{},withRpcError:(s,e)=>s+' '+e.message};
  vm.createContext(ctx);vm.runInContext(extract('function loadCatalog(root){','function showLog(root){'),ctx);
  await ctx.loadCatalog({});
  if(ctx.window.dmCatalog!==null||!ctx.state.pageNotice.catalog.includes('failed'))throw Error('catalog failure or stale entries hidden');
}
Promise.all([testCurrent({status:'failed',result:'fail'},'FAILED'),testCurrent({status:'done',result:'ok'},'DONE'),testSingleError(),testUpdateErrors(),testUpdateTimeout(),testProfileStatus(),testSlotDraft(),testDeviceSave(),testCatalogError()]).catch(e=>{console.error(e);process.exitCode=1;});
