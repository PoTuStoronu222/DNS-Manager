'use strict';
const fs=require('fs'), vm=require('vm');
const source=fs.readFileSync(process.argv[2],'utf8');
function extract(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);if(a<0||b<0)throw Error('missing '+start);return source.slice(a,b);}
const delay=()=>new Promise(resolve=>setTimeout(resolve,20));
async function testSingleError(){
  const ctx={state:{busy:false,jobRunning:false,checking:{},pageNotice:{}},window:{dmState:{}},render:()=>{},refresh:()=>Promise.resolve(),setAction:()=>{},withRpcError:(s,e)=>s+' '+e.message,callTestOne:()=>Promise.reject(Error('timeout'))};
  vm.createContext(ctx);vm.runInContext(extract('function testOne(id,root,origin,done){','function testCurrent(root){'),ctx);
  ctx.testOne('dns1',{},'catalog');await delay();
  if(ctx.state.jobRunning||!String(ctx.state.pageNotice.catalog).includes('timeout'))throw Error('single DNS error hidden');
}
async function testBadgeWithoutDuration(){
  const ctx={badge:(kind,label)=>({kind,label}),ping:x=>x+' мс'};
  vm.createContext(ctx);vm.runInContext(extract('function hasPing(v){','function settingName(n){'),ctx);
  if(ctx.stateBadge('OK','-1').kind!=='dm-ok')throw Error('answer marked unavailable without timing');
  if(ctx.stateBadge('BAD_DOH_RESPONSE','-1').kind!=='dm-bad')throw Error('bad answer not marked unavailable');
  if(ctx.stateBadge('','').kind!=='dm-off')throw Error('untested DNS not marked unknown');
}
async function testPollNavigation(){
  const root={__dmRoute:'dashboard'},newState={ntp_preset:'new'},oldState={slots:[]};let done=false;
  const ctx={state:{busy:false,jobRunning:true,checking:{x:{}},pageNotice:{}},window:{dmState:newState,dmCurrentRoot:root},currentRoute:()=> 'time',statusDetail:()=>0,callJob:()=>Promise.resolve({status:'done',result:'ok'}),callStatus:()=>Promise.resolve(oldState),render:()=>{},setAction:()=>{},setTimeout,stripAnsi:x=>x,rpcErrorText:()=>''};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob(root,'test_current',{mode:'current'},()=>{done=true;});await delay();
  if(!done||ctx.window.dmState!==newState||ctx.state.jobRunning||Object.keys(ctx.state.checking).length)throw Error('late job status replaced another route');
}
async function testLongCatalogProgress(total,statusFails){
  let calls=0,completed;const finished=new Promise(resolve=>{completed=resolve;});
  const state={busy:false,jobRunning:true,checking:{},pageNotice:{},activeTab:'catalog',catalogLoaded:true,fullTest:{status:'RUNNING',origin:'catalog'},catalogProgress:null};
  const ctx={state,window:{dmState:{},dmCatalog:{total:3}},currentRoute:()=> 'catalog',statusDetail:()=>0,callJob:()=>Promise.resolve(++calls<205?{status:'running',output:'Промежуточный результат: проверено 0 из '+total+' | работают 0 | ошибки 0'}:{status:'done',result:'ok',progress_done:String(total),progress_total:String(total),progress_ok:String(total),progress_fail:'0'}),callStatus:()=>statusFails?Promise.reject(Error('status timeout')):Promise.resolve({}),render:()=>{},renderCatalog:()=>{},loadCatalog:()=>{completed();},setAction:()=>{},setTimeout:f=>setImmediate(f),stripAnsi:x=>x,rpcErrorText:()=>''};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob({},'test_all',{mode:'all',origin:'catalog'});await Promise.race([finished,new Promise((_,reject)=>setTimeout(()=>reject(Error('catalog poll did not finish')),3000))]);
  if(calls!==205||state.fullTest.status!=='DONE'||state.catalogProgress.total!==total||state.catalogProgress.done!==total||state.catalogProgress.fail!==0)throw Error('long catalog check stopped early or reported wrong counts');
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
  ctx.window.dmRouteCache={doh:JSON.parse(store['dns-manager-route-2.34-doh'])};
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
    callPageMeta:()=>Promise.resolve({ok:true}),callLog:()=>Promise.resolve(failLog?{ok:false}:{ok:true,log:'log text',luci_version:'2.26',last_full_test:'100',watchdog_last_check:200,watchdog_last_category:'clean'}),
    stripAnsi:s=>s,Date,JSON,Promise,Object,Array,Error};
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  for(const route of ['devices','catalog','log'])await ctx.ensureStatusPromise(route);
  if(ctx.window.dmRouteCache.log.data.luci_version!=='2.26'||ctx.window.dmRouteCache.log.data.watchdog_last_check!==200||ctx.window.dmRouteCache.log.data.log!==undefined)throw Error('log header metadata missing or log duplicated in status');
  ctx.window.dmRouteCache=undefined;ctx.window.dmLanDevices=undefined;ctx.window.dmCatalog=undefined;ctx.state.logText='';ctx.state.logLoaded=false;ctx.state.catalogLoaded=false;
  for(const route of ['devices','catalog','log'])if(!ctx.cachedRouteStatus(route))throw Error(route+' cache missing after navigation');
  if(ctx.cachedRouteStatus('log').watchdog_last_category!=='clean')throw Error('log header metadata lost after navigation');
  if(ctx.window.dmLanDevices.devices[0].mac!=='aa'||ctx.window.dmCatalog.servers[0].id!=='dns'||ctx.state.logText!=='log text')throw Error('route-specific data not restored');
  ctx.state.category='security';if(ctx.cachedRouteStatus('catalog'))throw Error('wrong catalog category reused');ctx.state.category='all';
  failDevices=true;failCatalog=true;failLog=true;
  const previous={...store};for(const route of ['devices','catalog','log'])await ctx.ensureStatusPromise(route);
  for(const route of ['devices','catalog','log'])if(store['dns-manager-route-2.34-'+route]!==previous['dns-manager-route-2.34-'+route])throw Error('failed '+route+' replaced good cache');
}
async function testSequentialWarmup(){
  let active=0,max=0,calls=[],allowed=true;
  const rpc=(name,result)=>()=>{calls.push(name);active++;max=Math.max(max,active);return Promise.resolve().then(()=>{active--;return result;});};
  const ctx={window:{},state:{},Date,JSON,Promise,Object,Array,Error,stripAnsi:s=>s,
    callStatus:rpc('status',{ok:true}),callDohStatus:rpc('doh',{ok:true}),callNetworkStatus:rpc('network',{ok:true}),callTimeStatus:rpc('time',{ok:true}),
    callLanDevices:rpc('devices',{ok:true,devices:[]}),callCatalog:rpc('catalog',{ok:true,servers:[]}),callPageMeta:rpc('meta',{ok:true}),callLog:rpc('log',{ok:true,log:'x',luci_version:'2.26',watchdog_last_check:200})};
  vm.createContext(ctx);vm.runInContext(extract('function routeStatusCall(){','function checkUpdate(root,force){'),ctx);
  const catalog=await ctx.warmupFetch('catalog',()=>allowed),devices=await ctx.warmupFetch('devices',()=>allowed);
  if(max!==1||calls.join(',')!=='catalog,doh,meta,doh,devices'||!catalog.aux.catalog||!devices.aux.devices)throw Error('warmup was not sequential');
  const log=await ctx.warmupFetch('log',()=>allowed);
  if(log.data.luci_version!=='2.26'||log.data.watchdog_last_check!==200||log.data.log!==undefined||log.aux.log!=='x')throw Error('log warmup lost header metadata');
  let blocked=false;allowed=false;await ctx.warmupFetch('log',()=>allowed).catch(()=>{blocked=true;});if(!blocked||calls.filter(x=>x==='log').length!==1)throw Error('warmup ignored idle guard');
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
async function testResumeCache(){
  let resolveJob, feedback=[];
  const ctx={state:{busy:false,pageNotice:{}},window:{dmState:{}},rootAlive:()=>true,currentRoute:()=> 'network',
    callJob:()=>Promise.resolve({ok:true,status:'running',name:'set_cache'}),awaitSettingResult:()=>new Promise(r=>{resolveJob=r;}),
    setSettingFeedback:(key,msg,type)=>feedback.push({key,msg,type}),render:()=>{},refresh:()=>Promise.resolve(),withRpcError:(s,e)=>s+' '+e.message};
  vm.createContext(ctx);vm.runInContext(extract('function resumeAction(root){','function testAll(root,origin){'),ctx);
  ctx.resumeAction({});await delay();
  if(!ctx.state.busy||ctx.state.busySetting!=='dns_cache'||feedback[0].type!=='info')throw Error('cache action was not resumed');
  resolveJob({ok:true});await delay();
  if(ctx.state.busy||ctx.state.busySetting||feedback[feedback.length-1].type!=='ok')throw Error('cache resume did not complete');
}
async function testSettingConnectionLoss(){
  let calls=0,queue=[];
  const ctx={window:{setTimeout:fn=>queue.push(fn)},Date,Promise,callJob:()=>{calls++;return Promise.reject(Error('timeout'));}};
  vm.createContext(ctx);vm.runInContext(extract('function awaitSettingResult(reply){','function setSetting(name,en,root){'),ctx);
  let error='';const pending=ctx.awaitSettingResult({ok:true,job:'action'}).catch(e=>{error=e.message;});
  for(let i=0;i<4&&!error;i++){await delay();if(queue.length)queue.shift()();}
  await pending;
  if(calls!==3||!error.includes('может продолжаться'))throw Error('setting loss did not stop with an uncertain result');
}
async function testRegionalConnectionLoss(){
  let calls=0,queue=[];
  const ctx={state:{busy:true},window:{setTimeout:fn=>queue.push(fn)},Date,callJob:()=>{calls++;return Promise.reject(Error('timeout'));},
    renderProfiles:()=>{},refresh:()=>Promise.resolve(),withRpcError:(s,e)=>s+' '+e.message};
  vm.createContext(ctx);vm.runInContext(extract('function watchRegional(job,enabled,root){','function resumeRegional(root){'),ctx);
  ctx.watchRegional('regional',1,{});
  for(let i=0;i<4&&ctx.state.busy;i++){await delay();if(queue.length)queue.shift()();}
  await delay();
  if(calls!==3||ctx.state.busy||!ctx.state.regionalNotice.includes('может продолжаться'))throw Error('regional loss left the interface locked');
}
async function testProfileMissingJob(){
  const ctx={state:{busy:true,jobRunning:true,checking:{},pageNotice:{}},window:{dmState:{}},setAction:()=>{},render:()=>{}};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob({},'',{mode:'profile'});
  if(ctx.state.busy||ctx.state.jobRunning||!ctx.state.pageNotice.profiles)throw Error('missing profile job left interface locked');
}
async function testJobTransientError(){
  let calls=0,queue=[],finished=null;
  const ctx={state:{busy:false,jobRunning:true,checking:{item:{}},pageNotice:{}},window:{dmState:{}},setAction:()=>{},render:()=>{},
    setTimeout:fn=>queue.push(fn),currentRoute:()=> 'slots',statusDetail:()=>0,callStatus:()=>Promise.resolve({ok:true}),
    callJob:()=>{calls++;if(calls===13)return Promise.reject(Error('temporary'));if(calls===14)return Promise.resolve({ok:false,error:'temporary'});return Promise.resolve(calls<15?{status:'running'}:{status:'done',result:'ok'});}};
  vm.createContext(ctx);vm.runInContext(extract('function pollJob(root,job,meta,done){','function resumeRunningProfile(root){'),ctx);
  ctx.pollJob({},'test_one',{mode:'one',dns_id:'item'},(st,j)=>{finished=j;});
  for(let i=0;i<16&&!finished;i++){await delay();if(queue.length)queue.shift()();}
  await delay();
  if(!finished||finished.status!=='done'||calls!==15||ctx.state.jobRunning)throw Error('transient RPC failure stopped a running job');
}
async function testUninstallUnresponsiveStatus(){
  let now=0,timers=[];
  const clock={setTimeout:(fn,ms)=>{const item={fn,ms};timers.push(item);return item;},clearTimeout:item=>{timers=timers.filter(x=>x!==item);}};
  const ctx={state:{busy:false},window:Object.assign({dmState:{}},clock),Date:{now:()=>now},Promise,
    renderDoH:()=>{},callUninstall:()=>Promise.resolve({ok:true,status_url:'/status'}),fetch:()=>new Promise(()=>{}),withRpcError:(s,e)=>s+' '+e.message};
  vm.createContext(ctx);vm.runInContext(extract('function uninstallManager(root){','function resetDnsCore(root){'),ctx);
  ctx.uninstallManager({});await delay();
  if(!ctx.state.busy||timers.length!==1)throw Error('uninstall did not start polling');
  timers.shift().fn();const timeout=timers.find(x=>x.ms===10000);if(!timeout)throw Error('uninstall status has no request timeout');
  timeout.fn();await delay();now=181000;
  const retry=timers.find(x=>x.ms===2000);if(!retry)throw Error('uninstall did not retry timed-out status');
  retry.fn();
  if(ctx.state.busy||ctx.state.uninstall.status!=='failed'||!ctx.state.uninstall.message.includes('может продолжаться'))throw Error('uninstall remained locked or concealed uncertainty');
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
async function testLogScroll(){
  let current=null;
  const panel={querySelector:()=>current,set innerHTML(v){current=null;},appendChild(card){current=card.log;}};
  const ctx={state:{pageNotice:{},logLoaded:true,logText:'old\nnew'},window:{setTimeout:fn=>fn()},stripAnsi:s=>s,
    E:(tag,attrs,text)=>({scrollTop:0,scrollHeight:1000,clientHeight:100,text}),
    card:(name,children)=>({log:children[children.length-1]})};
  vm.createContext(ctx);vm.runInContext(extract('function renderLog(root){','function renderJobIdle(root,st){'),ctx);
  ctx.renderLog({querySelector:()=>panel});if(current.scrollTop!==1000)throw Error('log did not open at newest entries');
  current.scrollTop=100;ctx.renderLog({querySelector:()=>panel});if(current.scrollTop!==100)throw Error('log refresh disturbed manual scrolling');
}
async function testHeaderCheckKind(){
  let children=[];
  const header={innerHTML:'',appendChild:x=>{children=x.children;}};
  const ctx={E:(tag,attrs,children)=>({children}),dateText:t=>t?String(t):'—',shortVal:x=>x||'—'};
  vm.createContext(ctx);vm.runInContext(extract('function renderHeader(root,st){','function setActiveTab(root,name){'),ctx);
  function text(st){ctx.renderHeader({querySelector:()=>header},st);return children.map(x=>x.children).join(' ');}
  if(!text({last_full_test:100,last_full_test_scope:'all'}).includes('Проверка всего каталога: 100'))throw Error('full check label missing');
  if(!text({last_full_test:100,last_full_test_scope:'clean'}).includes('Проверка категории: 100 · Без фильтрации'))throw Error('category check label missing');
  if(!text({last_full_test:100,watchdog_last_check:200,watchdog_last_category:'clean'}).includes('Автопроверка слотов: 200 · Без фильтрации'))throw Error('automatic check label missing');
  if(!text({}).includes('Проверка DNS: не выполнялась'))throw Error('empty check label missing');
}
async function testDoHRemove(){
  let request;
  const ctx={state:{busy:false,jobRunning:false,pageNotice:{}},window:{dmState:{}},slotLabel:s=>'DNS '+s,confirmAction:(title,rows,fn)=>fn(),renderDoH:()=>{},callSlot:(...args)=>{request=args;return Promise.resolve({ok:true});},awaitSettingResult:x=>Promise.resolve(x),setAction:()=>{},refresh:()=>Promise.resolve(),withRpcError:(s,e)=>s+e};
  vm.createContext(ctx);vm.runInContext(extract('function removeSelectedSlot(d,root){','// Public resolver addresses'),ctx);
  ctx.removeSelectedSlot({slot:'1',id:'old',name:'Old'},{});await delay();
  if(!request||request.join('|')!=='1||old'||ctx.state.busy||!ctx.state.pageNotice.doh.includes('удалён'))throw Error('DoH removal did not preserve expected slot id or report success');
}
async function testBackgroundNavigation(){
  for(const id of ['update','combined']){
    let response={ok:true,status:'running'}, timers=[], notices=[], starts=0;
    const root={alive:true},state={updatingAll:false,jobRunning:false,busy:false,pageNotice:{}};
    const ctx={state,window:{dmState:{},setTimeout:fn=>timers.push(fn)},rootAlive:r=>r.alive,
      setTimeout,clearTimeout,callJob:()=>Promise.resolve(response),globalUpdateNotice:(m,k)=>notices.push([m,k]),
      renderOverview:()=>{},renderDoH:()=>{},refresh:()=>Promise.resolve(),
      displayDnsRows:()=>[{slot:'1',id:'one'}],callBackgroundUpdate:()=>{starts++;return Promise.resolve({ok:true});},
      callCombinedTest:()=>{starts++;return Promise.resolve({ok:true});}};
    vm.createContext(ctx);vm.runInContext(extract('function backgroundRequest(fn){','function uninstallManager(root){'),ctx);
    vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
    if(id==='update'){ctx.updateAll(root);ctx.updateAll(root);}else{ctx.testCurrent(root);ctx.testCurrent(root);}
    await delay();if(starts!==1||!timers.length)throw Error(id+' did not start once or show progress');
    root.alive=false;timers.shift()();response={ok:true,status:'done',result:'ok',output:'{"message":"Готово"}'};
    const next={alive:true};ctx.watchBackground(next,id);await delay();
    if(state.updatingAll||state.jobRunning)throw Error(id+' remained locked after return');
    if(id==='update'&&!notices.some(n=>n[0].includes('Готово')))throw Error('update result missing after return');
    if(id==='combined'&&state.currentTest.status!=='DONE')throw Error('DNS result missing after return');
  }
}
async function testBackgroundFailure(){
  let timers=[],notices=[];const root={alive:true},state={updatingAll:false,jobRunning:false,busy:false,pageNotice:{}};
  const ctx={state,window:{dmState:{},setTimeout:f=>timers.push(f)},rootAlive:r=>r.alive,setTimeout,clearTimeout,
    callJob:()=>Promise.resolve({ok:true,status:'failed',result:'fail',output:'{"message":"Ошибка загрузки"}'}),
    globalUpdateNotice:(m,k)=>notices.push([m,k]),renderOverview:()=>{},renderDoH:()=>{},refresh:()=>Promise.resolve(),
    callBackgroundUpdate:()=>Promise.resolve({ok:true})};
  vm.createContext(ctx);vm.runInContext(extract('function backgroundRequest(fn){','function uninstallManager(root){'),ctx);
  await ctx.updateAll(root);await delay();
  if(state.updatingAll||!notices.some(n=>n[1]==='error'&&n[0].includes('Ошибка загрузки')))throw Error('background failure not shown');
}
async function testBackgroundUnknown(){
  const root={alive:true},state={jobRunning:true,updatingAll:false,busy:false,pageNotice:{},currentTest:{status:'RUNNING'}};
  const ctx={state,window:{dmState:{},setTimeout:()=>{}},rootAlive:r=>r.alive,setTimeout,clearTimeout,
    callJob:()=>Promise.resolve({ok:false,error:'missing'}),globalUpdateNotice:()=>{},renderOverview:()=>{},renderDoH:()=>{},refresh:()=>Promise.resolve()};
  vm.createContext(ctx);vm.runInContext(extract('function backgroundRequest(fn){','function uninstallManager(root){'),ctx);
  ctx.watchBackground(root,'combined');await delay();
  if(state.jobRunning||state.currentTest.status!=='UNKNOWN'||!state.pageNotice.doh.includes('может продолжаться'))throw Error('unknown DNS result locked button or reported success');
}
async function testBackgroundStartTimeout(){
  for(const id of ['update','combined']){
    let timeoutFn,scheduled=[];const root={alive:true},state={updatingAll:false,jobRunning:false,busy:false,pageNotice:{}};
    const ctx={state,window:{dmState:{},setTimeout:f=>scheduled.push(f)},rootAlive:r=>r.alive,
      setTimeout:(f)=>{timeoutFn=f;return 1;},clearTimeout:()=>{},callJob:()=>Promise.resolve({ok:true,status:'running'}),
      globalUpdateNotice:()=>{},renderOverview:()=>{},renderDoH:()=>{},refresh:()=>Promise.resolve(),
      displayDnsRows:()=>[{id:'one',slot:'1'}],callBackgroundUpdate:()=>new Promise(()=>{}),callCombinedTest:()=>new Promise(()=>{})};
    vm.createContext(ctx);vm.runInContext(extract('function backgroundRequest(fn){','function uninstallManager(root){'),ctx);
    vm.runInContext(extract('function testCurrent(root){','function pollJob(root,job,meta,done){'),ctx);
    const pending=id==='update'?ctx.updateAll(root):ctx.testCurrent(root);
    if(!timeoutFn)throw Error('start timeout not armed');timeoutFn();await pending;await delay();
    if(id==='update'&&!state.updatingAll)throw Error('running update lost after start timeout');
    if(id==='combined'&&!state.jobRunning)throw Error('running DNS check lost after start timeout');
  }
}
async function testResumeCatalog(){
  for(const status of ['running','done']){
    let polled=0;const root={},state={jobRunning:false,pageNotice:{}};
    const ctx={state,rootAlive:()=>true,backgroundRequest:f=>f(),callJob:()=>Promise.resolve({ok:true,status,result:status==='done'?'ok':''}),renderCatalog:()=>{},pollJob:()=>{polled++;}};
    vm.createContext(ctx);vm.runInContext(extract('function resumeCatalogTest(root){','function testAll(root,origin){'),ctx);
    ctx.resumeCatalogTest(root);await delay();
    if(status==='running'&&(!state.jobRunning||polled!==1))throw Error('catalog job was not resumed');
    if(status==='done'&&(state.fullTest.status!=='DONE'||!state.pageNotice.catalog.includes('завершена')))throw Error('catalog result was not restored');
  }
}
async function testRegionalReapply(){
  const buttons=[],calls=[],state={busy:false};
  const ctx={state,regionalMode:'isp',hasGeneral:true,root:{},pch:[],E:()=>({appendChild:x=>buttons.push(x)}),btn:(text,cls,click,opts)=>({text,cls,click,opts}),setRegional:(v)=>calls.push(v)};
  vm.createContext(ctx);vm.runInContext(extract("  var regionalChoices=E('div',{'class':'dm-seg'});","  pch.push(E('p',{'class':'dm-hint'},regionalMode==='legacy'"),ctx);
  const active=buttons.find(b=>b.text==='DNS провайдера');
  if(!active||active.opts.disabled)throw Error('current regional mode cannot be reapplied after update');
  active.click();if(calls.join(',')!=='3')throw Error('reapplying provider DNS used the wrong mode');
  buttons.length=0;calls.length=0;ctx.regionalMode='legacy';
  vm.runInContext(extract("  var regionalChoices=E('div',{'class':'dm-seg'});","  pch.push(E('p',{'class':'dm-hint'},regionalMode==='legacy'"),ctx);
  const legacy=buttons.find(b=>b.text==='Применить повторно');
  if(!legacy||legacy.opts.disabled)throw Error('legacy regional DoH cannot be reapplied');
  legacy.click();if(calls.join(',')!=='1')throw Error('reapplying legacy regional DoH used the wrong mode');
}
Promise.all([testRegionalReapply(),testResumeCatalog(),testBackgroundStartTimeout(),testBackgroundUnknown(),testBackgroundNavigation(),testBackgroundFailure(),testDoHRemove(),testSingleError(),testBadgeWithoutDuration(),testPollNavigation(),testLongCatalogProgress(117),testLongCatalogProgress(5,true),testRouteCache(),testCachedReadOnly(),testAdditionalRouteCache(),testSequentialWarmup(),testWarmupResourceGuard(),testResumeCache(),testSettingConnectionLoss(),testRegionalConnectionLoss(),testProfileMissingJob(),testJobTransientError(),testUninstallUnresponsiveStatus(),testProfileStatus(),testSlotDraft(),testDeviceSave(),testCatalogError(),testFoldState(),testCustomDnsFeedback(),testBootstrapForm(),testLogScroll(),testHeaderCheckKind()]).catch(e=>{console.error(e);process.exitCode=1;});
