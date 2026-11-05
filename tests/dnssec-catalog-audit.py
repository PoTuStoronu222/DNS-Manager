# Developer-only observation tool; does not classify or modify the catalog.
import urllib.request, struct, concurrent.futures, sys, json
from pathlib import Path
catalog=Path(sys.argv[1]); out=Path(sys.argv[2]); rows=[]
for line in catalog.read_text(encoding='utf-8').splitlines():
    p=line.split('|')
    if len(p)==7 and not line.startswith('#'): rows.append(p)
def probe(url, host, cd=False):
    q=struct.pack('!HHHHHH',0x6172,0x0130 if cd else 0x0120,1,0,0,0)+b''.join(bytes([len(x)])+x.encode() for x in host.split('.'))+b'\0'+struct.pack('!HH',1,1)
    req=urllib.request.Request(url,data=q,headers={'Content-Type':'application/dns-message','Accept':'application/dns-message','User-Agent':'DNSSEC-audit/1'})
    try:
        with urllib.request.urlopen(req,timeout=5) as r:
            if r.headers.get_content_type()!='application/dns-message': return 'content-type'
            b=r.read(65537)
        if len(b)<12 or b[:2]!=q[:2]: return 'invalid'
        flags=struct.unpack('!H',b[2:4])[0]
        if not flags&0x8000: return 'invalid'
        return '%d/%d'%(flags&15,bool(flags&32))
    except Exception as e: return type(e).__name__
def worker(p):
    good=probe(p[4],'cloudflare.com')
    if good!='0/1': return {'id':p[0],'name':p[3],'url':p[4],'valid':good,'status':'unconfirmed'}
    bad=probe(p[4],'dnssec-failed.org'); cd=probe(p[4],'dnssec-failed.org',True)
    return {'id':p[0],'name':p[3],'url':p[4],'valid':good,'invalid':bad,'checking_disabled':cd,'status':'observed' if bad.startswith('2/') and cd.startswith('0/') else 'unconfirmed'}
results=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    jobs={pool.submit(worker,p):p for p in rows}
    for f in concurrent.futures.as_completed(jobs):
        v=f.result();results.append(v)
        if v['status']=='observed': print('observed:',v['id'],v['name'],flush=True)
out.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print('count',len(results),'observed',sum(r['status']=='observed' for r in results),flush=True)