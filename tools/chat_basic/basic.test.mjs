import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { validateFile, MAX } from '../../supabase/functions/_shared/chat_basic/validate.mjs';
import { attachmentHandler, allowedBrowserOrigin, sha256, paths, CHUNK_BYTES, chunkLength } from '../../supabase/functions/_shared/chat_basic/protocol.mjs';
const pdf=Buffer.from('%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\n2 0 obj << /Type /Pages >> endobj\n%%EOF\n');
const mimeDocx='application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const mimeXlsx='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
function crc(bytes){let c=-1;for(const b of bytes){c^=b;for(let i=0;i<8;i++) c=(c>>>1)^(0xedb88320&-(c&1));}return(c^-1)>>>0;}
function zip(entries){
 const locals=[],centrals=[];let offset=0;
 for(const [name,value] of Object.entries(entries)){
  const n=Buffer.from(name),data=Buffer.from(value),local=Buffer.alloc(30),central=Buffer.alloc(46);
  local.writeUInt32LE(0x04034b50);local.writeUInt16LE(20,4);local.writeUInt32LE(crc(data),14);local.writeUInt32LE(data.length,18);local.writeUInt32LE(data.length,22);local.writeUInt16LE(n.length,26);
  central.writeUInt32LE(0x02014b50);central.writeUInt16LE(20,4);central.writeUInt16LE(20,6);central.writeUInt32LE(crc(data),16);central.writeUInt32LE(data.length,20);central.writeUInt32LE(data.length,24);central.writeUInt16LE(n.length,28);central.writeUInt32LE(offset,42);
  locals.push(local,n,data);centrals.push(central,n);offset+=local.length+n.length+data.length;
 }
 const directory=Buffer.concat(centrals),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(Object.keys(entries).length,8);end.writeUInt16LE(Object.keys(entries).length,10);end.writeUInt32LE(directory.length,12);end.writeUInt32LE(offset,16);
 return Buffer.concat([...locals,directory,end]);
}
function office(ext,extra={}){
 const doc=ext==='docx';return zip({'[Content_Types].xml':`<Types><Override ContentType="application/vnd.openxmlformats-officedocument.${doc?'wordprocessingml.document':'spreadsheetml.sheet'}.main+xml"/></Types>`,
 '_rels/.rels':'<Relationships/>',[doc?'word/document.xml':'xl/workbook.xml']:doc?'<w:document/>':'<workbook/>',...extra});
}
function png(){
 const chunk=(name,data)=>{const head=Buffer.alloc(4),end=Buffer.alloc(4),type=Buffer.from(name);head.writeUInt32BE(data.length);end.writeUInt32BE(crc(Buffer.concat([type,data])));return Buffer.concat([head,type,data,end]);};
 const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(1);ihdr.writeUInt32BE(1,4);ihdr[8]=8;ihdr[9]=2;
 return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(Buffer.from([0,255,0,0]))),chunk('IEND',Buffer.alloc(0))]);
}
const jpeg=Buffer.from([255,216,255,192,0,11,8,0,1,0,1,1,1,17,0,255,218,0,8,1,1,0,0,63,0,0,255,217]);
for(const [name,bytes,mime] of [['a.jpg',jpeg,'image/jpeg'],['a.jpeg',jpeg,'image/jpeg'],['a.png',png(),'image/png'],['a.pdf',pdf,'application/pdf'],['a.docx',office('docx'),mimeDocx],['a.xlsx',office('xlsx'),mimeXlsx]]){
 test(`${name} passes bounded structural/type validation only`,()=>assert.equal(validateFile(bytes,name,mime),mime));
}
test('5 MiB exact limit enforced; unsupported/executable/legacy/macro extensions fail',()=>{
 const big=Buffer.alloc(MAX,32);pdf.subarray(0,-6).copy(big);Buffer.from('%%EOF\n').copy(big,MAX-6);
 assert.equal(MAX,5242880);assert.equal(validateFile(big,'a.pdf','application/pdf'),'application/pdf');
 assert.throws(()=>validateFile(Buffer.alloc(MAX+1),'a.pdf','application/pdf'));
 for(const name of ['a.doc','a.xls','a.docm','a.xlsm','a.exe','a.svg','../a.pdf']) assert.throws(()=>validateFile(pdf,name,'application/pdf'));
 assert.throws(()=>validateFile(Buffer.from('MZexecutable'),'renamed.pdf','application/pdf'));
 assert.throws(()=>validateFile(pdf,'a.pdf','image/png'));
});
for(const ext of ['docx','xlsx']) test(`${ext} rejects renamed package, macros, external entities and malformed ZIP`,()=>{
 const mime=ext==='docx'?mimeDocx:mimeXlsx;
 for(const extra of [{'word/vbaProject.bin':'test'},{'word/a.xml':'<!DOCTYPE x><x/>'},{'_rels/.rels':'<Relationship TargetMode="External"/>'}]) assert.throws(()=>validateFile(office(ext,extra),`a.${ext}`,mime));
 assert.throws(()=>validateFile(office(ext==='docx'?'xlsx':'docx'),`a.${ext}`,mime));
 assert.throws(()=>validateFile(Buffer.concat([Buffer.from('MZexecutable'),office(ext)]),`a.${ext}`,mime));
 assert.throws(()=>validateFile(office(ext,{'word/payload.js':'script'}),`a.${ext}`,mime));
 const corrupted=office(ext);corrupted[35]^=1;assert.throws(()=>validateFile(corrupted,`a.${ext}`,mime));
});
test('malformed PNG, huge dimensions and active-content PDF reject',()=>{
 const invalid=png();invalid[20]^=1;assert.throws(()=>validateFile(invalid,'a.png','image/png'));
 assert.throws(()=>validateFile(Buffer.from(pdf.toString().replace('endobj','/JavaScript endobj')),'a.pdf','application/pdf'));
});
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
test('origin allowlist accepts loopback ports and only the exact configured public origin',()=>{
 const configured='https://jobmate.example';
 for(const host of ['localhost','127.0.0.1']) for(const port of ['',':1',':80',':7357',':54321',':65535']) {
  assert.equal(allowedBrowserOrigin(`http://${host}${port}`,configured),true);
 }
 assert.equal(allowedBrowserOrigin(configured,configured),true);
 for(const origin of ['null','*','http://localhost:0','http://localhost:65536','http://localhost:-1',
  'http://localhost:12x','http://localhost:','http://localhost.evil.test:7357','http://127.0.0.1.evil.test',
  'http://127.1:7357','http://2130706433:7357','http://localhost@evil.test','http://user@localhost:7357',
  'http://localhost:7357/path','http://localhost:7357?x=1','http://localhost:7357#x',
  'http://192.168.1.2:7357','https://evil.test','https://jobmate.example.evil.test',
  'https://jobmate.example/path','https://jobmate.example:444','https://jobmate.example/']) {
  assert.equal(allowedBrowserOrigin(origin,configured),false,origin);
 }
 assert.equal(allowedBrowserOrigin('https://evil.test','*'),false);
});
test('CORS preflight works while disabled without auth/RPC/Storage and never reflects disallowed origins',async()=>{
 const fail=async()=>{throw Error('must not execute');};
 const handler=attachmentHandler({enabled:false,origin:'https://jobmate.example',authenticate:fail,userRpc:fail,serviceRpc:fail,putImmutable:fail});
 const preflight=origin=>new Request('https://edge.example/',{method:'OPTIONS',headers:{origin,
  'access-control-request-method':'POST','access-control-request-headers':'authorization, x-attachment-id, content-type'}});
 for(const origin of ['http://localhost:51987','http://127.0.0.1:61234','https://jobmate.example']) {
  const response=await handler(preflight(origin));assert.equal(response.status,204);
  assert.equal(response.headers.get('access-control-allow-origin'),origin);assert.equal(response.headers.get('vary'),'Origin');
  const disabled=await handler(new Request('https://edge.example/',{method:'POST',headers:{origin}}));
  assert.equal(disabled.status,503);assert.equal(disabled.headers.get('access-control-allow-origin'),origin);
 }
 const rejected=await handler(preflight('https://evil.test'));assert.equal(rejected.status,403);
 assert.equal(rejected.headers.has('access-control-allow-origin'),false);
 for(const headers of [{origin:'http://localhost:54321','access-control-request-method':'DELETE'},
  {origin:'http://localhost:54321','access-control-request-headers':'x-cleanup-secret'}]) {
  assert.equal((await handler(new Request('https://edge.example/',{method:'OPTIONS',headers}))).status,403);
 }
});
test('allowed dynamic-port and native requests still require authentication before any RPC',async()=>{
 let authenticated=0,rpcs=0;
 const handler=attachmentHandler({enabled:true,origin:'',authenticate:async()=>{authenticated++;throw Error('no JWT');},
  userRpc:async()=>{rpcs++;},serviceRpc:async()=>{rpcs++;}});
 for(const origin of ['http://localhost:58888','http://127.0.0.1:65535',null]){
  const response=await handler(new Request('https://edge.example/?op=status',{method:'POST',
   headers:origin?{origin}:{}}));assert.equal(response.status,503);
 }
 assert.equal(authenticated,3);assert.equal(rpcs,0);
 const blocked=await handler(new Request('https://edge.example/',{method:'POST',headers:{origin:'https://evil.test'}}));
 assert.equal(blocked.status,403);assert.equal(authenticated,3);
});
function fixture(){
 const row={attachment_id:id(1),conversation_id:id(2),sender_id:id(3),size_bytes:pdf.length,original_name:'a.pdf',mime_type:'application/pdf',state:'pending',can_upload:true,
 validation_scope:'basic-type-validation-no-antivirus-v1',expected_sha256:createHash('sha256').update(pdf).digest('hex')};
 const objects=new Map(),calls=[];
 const deps={enabled:true,origin:'http://local.test',authenticate:async()=>{},authorizeCleanup:async()=>{throw Error('denied');},
 userRpc:async(_,name)=>{calls.push(name);if(name==='prepare_chat_attachment_validation_basic_v1'){row.state='validating';return{...row,validation_token:id(4)};}return{...row};},
 serviceRpc:async(name,args)=>{calls.push(name);if(name==='finish_chat_attachment_validation_basic_v1'){assert.equal(args.p_validator_version,'basic-type-validation-no-antivirus-v1');row.state=args.p_verdict;}},
 putImmutable:async(path,bytes)=>{if(objects.has(path)&&await sha256(objects.get(path))!==await sha256(bytes))throw Error('conflict');objects.set(path,bytes);},
 download:async path=>{if(!objects.has(path))throw Error('missing');return objects.get(path);},
 validate:async(bytes,data)=>{const receipt={sha256:await sha256(bytes),size_bytes:bytes.length,mime_type:data.mime_type,engine:'basic-type-validation-no-antivirus-v1'};
  try{validateFile(bytes,data.original_name,data.mime_type);return{...receipt,verdict:'validated'};}catch(_){return{...receipt,verdict:'rejected'};}}
 };
 const run=(op,body=pdf)=>attachmentHandler(deps)(new Request(`http://local.test/?op=${op}`,{method:'POST',body,headers:{origin:deps.origin,'x-attachment-id':id(1),'x-chunk-index':'0'}}));
 return{row,objects,calls,deps,run};
}
test('real basic validator integration: uploaded bytes validate but are not sent by Edge',async()=>{
 const f=fixture();assert.equal((await f.run('upload')).status,200);assert.equal((await f.run('validate')).status,200);
 assert.equal(f.row.state,'validated');assert.equal(f.objects.has(`${paths(f.row)}file`),true);assert.equal(f.calls.some(x=>x.startsWith('send_')),false);
});
test('disabled/auth failure cannot upload; validation outage cannot validate or send',async()=>{
 const f=fixture();f.deps.enabled=false;assert.equal((await f.run('upload')).status,503);assert.equal(f.objects.size,0);
 f.deps.enabled=true;f.deps.authenticate=async()=>{throw Error('denied');};assert.equal((await f.run('upload')).status,503);
 f.deps.authenticate=async()=>{};await f.run('upload');f.deps.validate=async()=>{throw Error('Unavailable');};assert.equal((await f.run('validate')).status,503);assert.equal(f.row.state,'validating');assert.equal(f.objects.has(`${paths(f.row)}file`),false);
});
test('immutable replay deduplicates chunks, rejects changes and incomplete uploads',async()=>{
 const f=fixture();await f.run('upload');await f.run('upload');assert.equal(f.objects.size,1);
 const changed=Buffer.from(pdf);changed[0]^=1;assert.equal((await f.run('upload',changed)).status,503);
 const missing=fixture();assert.equal((await missing.run('validate')).status,503);assert.equal(missing.objects.size,0);
 assert.equal(chunkLength(CHUNK_BYTES+1,1),1);assert.throws(()=>chunkLength(MAX+1,0));
});
test('format mismatch is rejected by real validation, not given a fabricated success',async()=>{
 const f=fixture();f.row.original_name='a.docx';f.row.mime_type=mimeDocx;await f.run('upload');assert.equal((await f.run('validate')).status,200);assert.equal(f.row.state,'rejected');assert.equal(f.objects.has(`${paths(f.row)}file`),false);
});
test('cleanup preserves committed final objects and requires scheduler authorization',async()=>{
 const f=fixture(),removed=[];assert.equal((await f.run('cleanup')).status,503);
 f.deps.authorizeCleanup=async()=>{};f.deps.remove=async paths=>removed.push(...paths);
 f.deps.serviceRpc=async name=>name==='claim_expired_chat_attachments_basic_v1'?[{attachment_id:id(1),storage_path:`${paths(f.row)}file`,size_bytes:pdf.length,chunks_only:true}]:null;
 assert.equal((await f.run('cleanup')).status,200);assert.deepEqual(removed,[`${paths(f.row)}part.0`]);
});
