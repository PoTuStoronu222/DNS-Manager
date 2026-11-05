#!/usr/bin/env python3
"""Exercise dnssec_probe_local using real dig and a local synthetic DNS server."""
import pathlib, socket, struct, subprocess, tempfile, threading

source = pathlib.Path('dns-manager.sh').read_text(encoding='utf-8')
start = source.index('dnssec_probe_local() (')
end = source.index('\n)\n', start) + 3
function = source[start:end]
state = {'mode': 'valid', 'stop': False}
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('127.0.0.1', 0)); sock.settimeout(0.2)
port = sock.getsockname()[1]

def serve():
    while not state['stop']:
        try: msg, addr = sock.recvfrom(65535)
        except socket.timeout: continue
        if len(msg) < 12: continue
        pos=12; labels=[]
        while pos<len(msg) and msg[pos]:
            size=msg[pos]; labels.append(msg[pos+1:pos+1+size].decode('ascii')); pos+=size+1
        pos+=5; question=msg[12:pos]; name='.'.join(labels)
        cd=bool(struct.unpack('!H', msg[2:4])[0] & 0x10)
        bad=name=='dnssec-failed.org' and not cd and state['mode']!='accepts_bad'
        no_ad=state['mode']=='missing_ad'
        empty=state['mode']=='empty_cd' and cd
        flags=0x8182 if bad else (0x8190 if cd else (0x8180 if no_ad else 0x81a0))
        rr=b'' if bad or empty else b'\xc0\x0c'+struct.pack('!HHIH',1,1,60,4)+bytes([192,0,2,1])
        answer=msg[:2]+struct.pack('!HHHHH',flags,1,int(bool(rr)),0,0)+question+rr
        sock.sendto(answer,addr)

worker=threading.Thread(target=serve, daemon=True); worker.start()
try:
    with tempfile.TemporaryDirectory() as tmp:
        path=pathlib.Path(tmp)/'probe.sh'
        path.write_text(function+'\ndnssec_probe_local "$1"\n',encoding='utf-8')
        for mode in ('valid','missing_ad','accepts_bad','empty_cd'):
            state['mode']=mode
            rc=subprocess.run(['sh',str(path),str(port)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode
            if (rc==0) != (mode=='valid'): raise SystemExit('FAIL: '+mode+' exit '+str(rc))
    print('OK: real dig with local DNS wire responses')
finally:
    state['stop']=True; worker.join(timeout=1); sock.close()
