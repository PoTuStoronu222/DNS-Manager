'use strict';
const fs=require('fs'), vm=require('vm');
const source=fs.readFileSync(process.argv[2],'utf8');
function extract(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);if(a<0||b<0)throw Error('missing '+start);return source.slice(a,b);}
const delay=()=>new Promise(resolve=>setTimeout(resolve,20));
async function testCurrent(result,expected){
  const st={slots:[{id:'dns1',slot:'1',status:'OK',ping:'42'}],doh_instances:[]};let calls=0;
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:st},render:()=>{},setAction:()=>{},checkKey:id=>id,displayDnsRows:s=>s.slots||[],hasPing:x=>/^\d+$/.test(String(x)),callTestCurrent:()=>{calls++;return Promise.resolve({ok:true,job:'j'});},pollJob:(root,job,meta,done)=>done(st,result)};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
  ctx.testCurrent({});await delay();
  if(ctx.state.currentTest.status!==expected)throw Error('current DNS result: '+JSON.stringify(ctx.state.currentTest));
  if(calls!==1||ctx.state.jobRunning||Object.keys(ctx.state.checking).length)throw Error('saved slot was skipped or checking state remained');
}
async function testSingleError(){
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:{}},render:()=>{},refresh:()=>Promise.resolve(),setAction:()=>{},withRpcError:(s,e)=>s+' '+e.message,callTestOne:()=>Promise.reject(Error('timeout'))};
  vm.createContext(ctx);vm.runInContext(extract('function testOne(id,root,origin,done){','function testCurrent(root){'),ctx);
  ctx.testOne('dns1',{},'catalog');await delay();
  if(ctx.state.jobRunning||!String(ctx.state.pageNotice.catalog).includes('timeout'))throw Error('single DNS error hidden');
}
async function testMixedCurrent(){
  const st={rows:[{id:'slot1',slot:'1',status:'OK',ping:'12'},{id:'catalogid',slot:'',url:'https://dns.example/query',port:'5054',status:'OK',ping:'30'}]};
  let calls=[];
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:st},render:()=>{},setAction:()=>{},checkKey:(id,d)=>id||String(d.port),displayDnsRows:s=>s.rows||[],hasPing:x=>/^\d+$/.test(String(x)),callTestCurrent:()=>{calls.push('slot');return Promise.resolve({ok:true,job:'slots'});},callTestSystem:()=>{calls.push('system');return Promise.resolve({ok:true,job:'system'});},pollJob:(root,job,meta,done)=>done(st,{status:'done',result:'ok'})};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
  ctx.testCurrent({});await delay();
  if(calls.join(',')!=='slot,system'||ctx.state.currentTest.status!=='DONE'||ctx.state.currentTest.total!==2)throw Error('mixed DNS tests were not completed');
}
async function testCurrentNoJob(){
  const st={rows:[{id:'dns1',slot:'1',status:'OK',ping:'12'}]};
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:st},render:()=>{},setAction:()=>{},checkKey:id=>id,displayDnsRows:s=>s.rows||[],hasPing:x=>/^\d+$/.test(String(x)),callTestCurrent:()=>Promise.resolve({ok:true})};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function resumeRunningProfile(root){'),ctx);
  ctx.testCurrent({});await delay();
  if(ctx.state.currentTest.status!=='FAILED'||ctx.state.jobRunning||Object.keys(ctx.state.checking).length)throw Error('missing job left stale success or loading state');
}
async function testCurrentSystemOnly(){
  const st={rows:[{id:'',slot:'',url:'https://dns.example/query',port:'5054',status:'OK',ping:'30'}]};let calls=0;
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:st},render:()=>{},setAction:()=>{},checkKey:(id,d)=>id||d.port,displayDnsRows:s=>s.rows||[],hasPing:x=>/^\d+$/.test(String(x)),callTestSystem:()=>{calls++;return Promise.resolve({ok:true,job:'system'});},pollJob:(r,j,m,done)=>done(st,{status:'done',result:'ok'})};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
  ctx.testCurrent({});await delay();
  if(calls!==1||ctx.state.currentTest.status!=='DONE')throw Error('system-only DNS test did not complete');
}
async function testCurrentNavigation(){
  const root={},other={},oldState={rows:[{id:'dns1',slot:'1',status:'OK',ping:'12'}]},newState={watchdog:'1'};let finish;
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:oldState,dmCurrentRoot:root},render:()=>{},setAction:()=>{},checkKey:id=>id,displayDnsRows:s=>s.rows||[],hasPing:x=>/^\d+$/.test(String(x)),callTestCurrent:()=>Promise.resolve({ok:true,job:'j'}),pollJob:(r,j,m,done)=>{finish=done;}};
  vm.createContext(ctx);vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
  ctx.testCurrent(root);await delay();ctx.window.dmCurrentRoot=other;ctx.window.dmState=newState;finish(oldState,{status:'done',result:'ok'});await delay();
  if(ctx.window.dmState!==newState||ctx.state.currentTest.status!=='DONE'||ctx.state.jobRunning)throw Error('DNS completion overwrote a different page');
}
async function testPollNavigation(){
  const root={__dmRoute:'dashboard'},newState={ntp_preset:'new'},oldState={slots:[]};let done=false;
  const ctx={state:{busy:false,jobRunning:true,checking:{x:{}},pageNotice:{}},window:{dmState:newState,dmCurrentRoot:root},currentRoute:()=> 'time',statusDetail:()=>0,callJob:()=>Promise.resolve({status:'done',result:'ok'}),callStatus:()=>Promise.resolve(oldState),render:()=>{},setAction:()=>{},setTimeout,stripAnsi:x=>x,rpcErrorText:()=>''};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob(root,'test_current',{mode:'current'},()=>{done=true;});await delay();
  if(!done||ctx.window.dmState!==newState||ctx.state.jobRunning||Object.keys(ctx.state.checking).length)throw Error('late job status replaced another route');
}
async function testRouteCache(){
  let route='dashboard',resolveDashboard,resolveDoh,draws=[];
  const root={};
  const store={};
  const session={setLocalData:(k,v)=>{store[k]=JSON.stringify(v);},getLocalData:k=>store[k]?JSON.parse(store[k]):null};
  const ctx={session,window:{dmCurrentRoot:root},state:{statusError:'',statusFromCache:false},currentRoute:()=>route,rootAlive:()=>true,render:(r,s)=>draws.push(s),callStatus:()=>new Promise(r=>{resolveDashboard=r;}),callDohStatus:()=>new Promise(r=>{resolveDoh=r;}),callTimeStatus:()=>Promise.resolve({}),Date,JSON,Promise,Object,Error};
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  const a=ctx.ensureStatusPromise('dashboard'),b=ctx.ensureStatusPromise('doh');
  if(a===b||!resolveDashboard||!resolveDoh)throw Error('different routes shared one RPC');
  if(ctx.ensureStatusPromise('slots')!==b)throw Error('compatible pages issued duplicate RPCs');
  resolveDoh({ok:true,force_owner:'steer',slots:[{id:'one'}]});resolveDashboard({ok:true,force_owner:'none',slots:[]});
  await Promise.all([a,b]);
  const cached=ctx.cachedRouteStatus('slots');
  if(!cached||cached.force_owner!=='steer'||cached.__dmCachedRoute!=='slots')throw Error('compatible route cache missing');
  ctx.window.dmRouteCache=undefined;
  if(ctx.cachedRouteStatus('slots').force_owner!=='steer')throw Error('cache did not survive page navigation');
  ctx.window.dmRouteCache={doh:JSON.parse(store['dns-manager-route-2.14-doh'])};
  cached.slots.length=0;
  if(ctx.cachedRouteStatus('doh').slots.length!==1)throw Error('cache was mutated by view');
  ctx.applyStatusToCurrentRoot({ok:true,force_owner:'steer'},'doh');
  if(draws.length)throw Error('late response rendered on another route');
  ctx.applyStatusToCurrentRoot({ok:true,force_owner:'none',slots:[]},'dashboard');
  if(draws.length!==1||ctx.window.dmState.force_owner!=='none'||ctx.window.dmState.slots.length)throw Error('fresh empty values were not applied');
  ctx.window.dmRouteCache.doh.ts=Date.now()-301000;
  if(ctx.cachedRouteStatus('doh')!==null)throw Error('expired cache was reused');
  let rejected=false;await ctx.ensureStatusPromise('time').catch(()=>{rejected=true;});
  if(!rejected||ctx.cachedRouteStatus('time'))throw Error('invalid status was cached as valid');
}
async function testCachedReadOnly(){
  const controls=[{disabled:false},{disabled:false}],messages=[];
  const root={querySelector:()=>({appendChild:x=>messages.push(x)}),querySelectorAll:()=>controls};
  const ctx={state:{statusFromCache:true,statusError:'',activeTab:'dashboard'},currentRoute:()=> 'dashboard',renderHeader:()=>{},renderOverview:()=>{},setActiveTab:()=>{},E:(tag,attrs,text)=>({tag,attrs,text})};
  vm.createContext(ctx);vm.runInContext(extract('function render(root,st){','function routeStatusCall(){'),ctx);
  ctx.render(root,{ok:true});
  if(controls.some(x=>!x.disabled)||!messages.some(x=>String(x.text).includes('предыдущие данные')))throw Error('cached state was not marked read-only');
}
async function testAdditionalRouteCache(){
  const store={};let failDevices=false,failCatalog=false,failLog=false;
  const ctx={window:{},state:{category:'all',offset:0,limit:18,pageNotice:{}},session:{setLocalData:(k,v)=>{store[k]=JSON.stringify(v);},getLocalData:k=>store[k]?JSON.parse(store[k]):null},
    callDohStatus:()=>Promise.resolve({ok:true,slots:[]}),
    callLanDevices:()=>Promise.resolve(failDevices?{ok:false}:{ok:true,devices:[{mac:'aa'}]}),
    callCatalog:()=>Promise.resolve(failCatalog?{ok:false}:{ok:true,servers:[{id:'dns'}]}),
    callPageMeta:()=>Promise.resolve({ok:true}),callLog:()=>Promise.resolve(failLog?{ok:false}:{ok:true,log:'log text'}),
    stripAnsi:s=>s,Date,JSON,Promise,Object,Array,Error};
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  for(const route of ['devices','catalog','log'])await ctx.ensureStatusPromise(route);
  ctx.window.dmRouteCache=undefined;ctx.window.dmLanDevices=undefined;ctx.window.dmCatalog=undefined;ctx.state.logText='';ctx.state.logLoaded=false;ctx.state.catalogLoaded=false;
  for(const route of ['devices','catalog','log'])if(!ctx.cachedRouteStatus(route))throw Error(route+' cache missing after navigation');
  if(ctx.window.dmLanDevices.devices[0].mac!=='aa'||ctx.window.dmCatalog.servers[0].id!=='dns'||ctx.state.logText!=='log text')throw Error('route-specific data not restored');
  ctx.state.category='security';if(ctx.cachedRouteStatus('catalog'))throw Error('wrong catalog category reused');ctx.state.category='all';
  failDevices=true;failCatalog=true;failLog=true;
  const previous={...store};for(const route of ['devices','catalog','log'])await ctx.ensureStatusPromise(route);
  for(const route of ['devices','catalog','log'])if(store['dns-manager-route-2.14-'+route]!==previous['dns-manager-route-2.14-'+route])throw Error('failed '+route+' replaced good cache');
}
async function testSequentialWarmup(){
  let active=0,max=0,calls=[],allowed=true;
  const rpc=(name,result)=>()=>{calls.push(name);active++;max=Math.max(max,active);return Promise.resolve().then(()=>{active--;return result;});};
  const ctx={window:{},state:{},Date,JSON,Promise,Object,Array,Error,stripAnsi:s=>s,
    callStatus:rpc('status',{ok:true}),callDohStatus:rpc('doh',{ok:true}),callNetworkStatus:rpc('network',{ok:true}),callTimeStatus:rpc('time',{ok:true}),
    callLanDevices:rpc('devices',{ok:true,devices:[]}),callCatalog:rpc('catalog',{ok:true,servers:[]}),callPageMeta:rpc('meta',{ok:true}),callLog:rpc('log',{ok:true,log:'x'})};
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  const catalog=await ctx.warmupFetch('catalog',()=>allowed),devices=await ctx.warmupFetch('devices',()=>allowed);
  if(max!==1||calls.join(',')!=='catalog,doh,meta,doh,devices'||!catalog.aux.catalog||!devices.aux.devices)throw Error('warmup was not sequential');
  let blocked=false;allowed=false;await ctx.warmupFetch('log',()=>allowed).catch(()=>{blocked=true;});if(!blocked||calls.includes('log'))throw Error('warmup ignored idle guard');
}
async function testWarmupResourceGuard(){
  let timers=[],reads=0,runtimeCalls=0,ram=20000,cpu=0,hidden=false;
  const root={},ctx={window:{dmCurrentRoot:null,setTimeout:f=>{timers.push(f);}},document:{get hidden(){return hidden;}},state:{},Date,JSON,Promise,Object,Array,Error,
    currentRoute:()=> 'dashboard',rootAlive:()=>true,callRuntime:()=>{runtimeCalls++;return Promise.resolve({ok:true,memory_available_kb:ram,cpu_load:cpu});},
    callDohStatus:()=>{reads++;return Promise.resolve({ok:true});}};
  ctx.window.dmCurrentRoot=root;
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  ctx.scheduleRouteWarmup(root);timers.shift()();await delay();
  if(reads)throw Error('warmup ran with low available memory');
  ram=100000;cpu=90;timers.shift()();await delay();
  if(reads)throw Error('warmup ran with high CPU');
  cpu=0;hidden=true;timers.shift()();await delay();
  if(reads||runtimeCalls!==2)throw Error('warmup ran in hidden tab');
  hidden=false;ctx.state.busy=true;timers.shift()();await delay();
  if(reads||runtimeCalls!==2)throw Error('warmup ran during action');
  ctx.state.busy=false;
  for(const flag of ['updatingAll','managerUpdating','hdpUpdating','lanDevicesLoading']){
    ctx.state[flag]=true;timers.shift()();await delay();
    if(reads||runtimeCalls!==2)throw Error('warmup ran during '+flag);
    ctx.state[flag]=false;
  }
  ctx.state.versionCheck={running:true};timers.shift()();await delay();
  if(reads||runtimeCalls!==2)throw Error('warmup ran during update check');
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
async function testFoldState(){
  const ctx={state:{},E:(tag,attrs,children)=>({tag,attrs,children,open:Object.prototype.hasOwnProperty.call(attrs,'open'),addEventListener(name,fn){this[name]=fn;}})};
  vm.createContext(ctx);vm.runInContext(extract('function foldSection(key,summary,content,classes){','function renderSlots(root,st){'),ctx);
  const first=ctx.foldSection('slot-1','Domains',{},'');
  if(first.open)throw Error('section should start closed');
  first.open=true;first.toggle();
  const second=ctx.foldSection('slot-1','Domains',{},'');
  if(!second.open)throw Error('open section not restored');
  second.open=false;second.toggle();
  if(ctx.foldSection('slot-1','Domains',{},'').open)throw Error('closed section not restored');
  if(ctx.foldSection('device-a','Device',{},'').open)throw Error('section state leaked to another entry');
}
async function testCustomDnsFeedback(){
  let reply={ok:false,error:'Этот DoH URL уже есть в каталоге: Пример'};
  const ctx={state:{busy:false,pageNotice:{}},window:{},renderCatalog:()=>{},refresh:()=>Promise.resolve(),setAction:()=>{},withRpcError:(s,e)=>s+e.message,callAddCustomDns:()=>Promise.resolve(reply)};
  vm.createContext(ctx);vm.runInContext(extract('function saveCustomDns(nameInput,urlInput,root){','function isUserDnsRecord(d){'),ctx);
  const name={value:'Мой DNS'},url={value:'https://example.org/dns-query'};
  ctx.saveCustomDns(name,url,{});await delay();
  if(ctx.state.customDnsNotice.type!=='error'||!ctx.state.customDnsNotice.text.includes('Пример')||ctx.state.customDnsDraft.url!==url.value||ctx.state.customDnsDraft.name!==name.value)throw Error('duplicate message or input lost');
  ctx.callAddCustomDns=()=>Promise.reject(Error('timeout'));ctx.saveCustomDns(name,url,{});await delay();
  if(ctx.state.customDnsNotice.type!=='error'||!ctx.state.customDnsNotice.text.includes('timeout')||ctx.state.customDnsDraft.url!==url.value)throw Error('RPC failure or input lost');
  ctx.callAddCustomDns=()=>Promise.resolve(reply);
  reply={ok:true,name:'Мой DNS'};ctx.saveCustomDns(name,url,{});await delay();
  if(ctx.state.customDnsNotice.type!=='ok'||ctx.state.customDnsDraft.url||ctx.state.customDnsDraft.name||ctx.state.category!=='custom')throw Error('custom DNS success feedback incorrect');
}
async function testBootstrapForm(){
  let sent=null;
  const ctx={state:{busy:false,jobRunning:false},window:{dmState:{}},E:(tag,attrs,children)=>({tag,attrs,children,value:attrs.value||'',checked:Object.prototype.hasOwnProperty.call(attrs,'checked'),disabled:false,addEventListener(k,f){this[k]=f;}}),btn:(label,klass,click)=>({tag:'button',click}),card:(title,children)=>({tag:'card',children}),foldSection:(key,summary,content)=>content,renderDoH:()=>{},refresh:()=>Promise.resolve(),awaitSettingResult:r=>Promise.resolve(r),withRpcError:(s,e)=>s+e.message,callBootstrap:(m,a,ids,extra)=>{sent=[m,a,ids,extra];return Promise.resolve({ok:true});}};
  vm.createContext(ctx);vm.runInContext(extract('var bootstrapPresets=[','function renderDoH(root,st){'),ctx);
  const tree=ctx.renderBootstrap({},{}),body=tree.children[0].children,select=body[2].children[0],choices=body[3].children,actions=body[5].children;
  select.value='choose';select.change();choices[0].children[0].checked=true;choices[0].children[0].change();choices[1].children[0].checked=true;choices[1].children[0].change();
  actions[0].value='9.9.9.9,1.1.1.1';actions[0].input();actions[1].click();await delay();
  if(!sent||sent[0]!=='custom'||sent[1].split(',').length!==9||!sent[1].includes('9.9.9.9')||ctx.state.bootstrapNotice.type!=='ok'||ctx.state.bootstrapDraft!==null)throw Error('bootstrap combined form values incorrect');
  if(sent[2]!=='cloudflare,google'||sent[3]!=='9.9.9.9,1.1.1.1')throw Error('bootstrap selection metadata lost');
  const restored=ctx.bootstrapSplitSelection(sent[1]);
  if(restored.ids.join(',')!=='cloudflare,google'||restored.addresses!=='9.9.9.9')throw Error('bootstrap combined selection was not restored');
  if(ctx.bootstrapSplitSelection('').mode!=='default')throw Error('default bootstrap mode lost');
  const all=ctx.bootstrapComposeSelection(ctx.bootstrapPresets.map(p=>p.id),'').split(',');
  if(all.length<30||all.length>48||all.some(ip=>!require('net').isIP(ip)))throw Error('invalid or excessive preset addresses');
  ctx.bootstrapPresets[0].ips='1.1.1.9,1.0.0.9';
  const withMetadata=ctx.bootstrapSplitSelection(sent[1],sent[2],sent[3],sent[1]);
  if(withMetadata.ids.join(',')!=='cloudflare,google'||withMetadata.addresses!==sent[3])throw Error('saved choices lost after provider update');
  const updated=ctx.renderBootstrap({}, {bootstrap_selected:sent[1],bootstrap_preset_ids:sent[2],bootstrap_extra:sent[3],bootstrap_metadata_snapshot:sent[1]});
  const updatedBody=updated.children[0].children, warning=updatedBody.find(x=>x.attrs&&x.attrs.class==='dm-inline-msg info');
  const updatedOptions=updatedBody.find(x=>x.attrs&&x.attrs.class==='dm-bootstrap-options').children;
  if(!warning||!updatedOptions[0].children[0].checked||!updatedOptions[1].children[0].checked)throw Error('updated preset selection or warning not displayed');
  const legacy=ctx.bootstrapSplitSelection(sent[1]);
  if(legacy.ids.join(',')!=='cloudflare,google'||legacy.addresses!=='9.9.9.9')throw Error('legacy choices lost after provider update');
  const stale=ctx.bootstrapSplitSelection(sent[1],'wrong','', 'not-the-current-snapshot');
  if(stale.ids.join(',')!=='cloudflare,google')throw Error('stale metadata was trusted');
  const before=sent.slice();ctx.bootstrapPresets.shift();
  const missing=ctx.renderBootstrap({}, {bootstrap_selected:before[1],bootstrap_preset_ids:before[2],bootstrap_extra:before[3],bootstrap_metadata_snapshot:before[1]});
  const missingBody=missing.children[0].children, missingOptions=missingBody.find(x=>x.attrs&&x.attrs.class==='dm-bootstrap-options').children;
  if(!missingOptions.some(x=>String(x.children[1].children).includes('cloudflare')))throw Error('removed preset was silently discarded');
  const applyRows=missingBody.filter(x=>x.attrs&&x.attrs.class==='dm-actions');sent=null;applyRows[applyRows.length-1].children[1].click();
  if(sent||ctx.state.bootstrapNotice.type!=='error')throw Error('removed preset applied without explicit removal');
}
Promise.all([testCurrent({status:'failed',result:'fail'},'FAILED'),testCurrent({status:'done',result:'ok'},'DONE'),testSingleError(),testMixedCurrent(),testCurrentNoJob(),testCurrentSystemOnly(),testCurrentNavigation(),testPollNavigation(),testRouteCache(),testCachedReadOnly(),testAdditionalRouteCache(),testSequentialWarmup(),testWarmupResourceGuard(),testUpdateErrors(),testUpdateTimeout(),testProfileStatus(),testSlotDraft(),testDeviceSave(),testCatalogError(),testFoldState(),testCustomDnsFeedback(),testBootstrapForm()]).catch(e=>{console.error(e);process.exitCode=1;});
