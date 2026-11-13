import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { validateFile, MAX } from './validate.mjs';
import { scannerServer, clamScanner } from './server.mjs';
import { attachmentHandler, chunkLength, paths, sha256, CHUNK_BYTES } from '../../supabase/functions/_shared/chat_attachments/protocol.mjs';

const pdf = Buffer.from('%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\n2 0 obj << /Type /Pages >> endobj\n%%EOF\n');
function crc(bytes) { let c = -1; for (const b of bytes) { c ^= b; for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); } return (c ^ -1) >>> 0; }
function zip(entries) {
  const locals = [], centrals = []; let offset = 0;
  for (const [name, value] of Object.entries(entries)) {
    const n = Buffer.from(name), data = Buffer.from(value), local = Buffer.alloc(30), central = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
    local.writeUInt32LE(crc(data), 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(n.length, 26);
    central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt32LE(crc(data), 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(n.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local,n,data); centrals.push(central,n); offset += local.length + n.length + data.length;
  }
  const directory = Buffer.concat(centrals), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(Object.keys(entries).length, 8); end.writeUInt16LE(Object.keys(entries).length, 10);
  end.writeUInt32LE(directory.length,12); end.writeUInt32LE(offset,16);
  return Buffer.concat([...locals,directory,end]);
}
function ooxml(ext, extra = {}) {
  const doc = ext === 'docx';
  return zip({ '[Content_Types].xml': `<Types><Override ContentType="application/vnd.openxmlformats-officedocument.${doc ? 'wordprocessingml.document' : 'spreadsheetml.sheet'}.main+xml"/></Types>`,
    '_rels/.rels': '<Relationships/>', [doc ? 'word/document.xml' : 'xl/workbook.xml']: '<document/>', ...extra });
}
test('structural PDF checks reject active content and malformed/renamed formats', () => {
  assert.equal(validateFile(pdf, 'a.pdf', 'application/pdf'), 'application/pdf');
  for (const bytes of [Buffer.from('MZtest'),Buffer.from('%PDF-1.7\n%%EOF'),Buffer.from(pdf.toString().replace('endobj', '/JavaScript endobj'))]) {
    assert.throws(() => validateFile(bytes, 'a.pdf', 'application/pdf'));
  }
  assert.throws(() => validateFile(pdf, '../a.pdf', 'application/pdf'));
  assert.throws(() => validateFile(pdf, 'a.pdf', 'image/png'));
  assert.throws(() => validateFile(Buffer.alloc(MAX + 1), 'a.pdf','application/pdf'));
});
for (const [ext,mime] of [['docx','application/vnd.openxmlformats-officedocument.wordprocessingml.document'],['xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']]) {
  test(`${ext} parses package and rejects macros/external content/wrong type/corruption`, () => {
    assert.equal(validateFile(ooxml(ext), `a.${ext}`, mime), mime);
    for (const extra of [{ 'word/vbaProject.bin':'malicious' }, { 'word/a.xml':'<!DOCTYPE x><x/>' }, { '_rels/.rels':'<Relationship TargetMode="External"/>' }]) {
      assert.throws(() => validateFile(ooxml(ext, extra), `a.${ext}`, mime));
    }
    assert.throws(() => validateFile(ooxml(ext === 'docx' ? 'xlsx' : 'docx'), `a.${ext}`, mime));
    const corrupt = ooxml(ext); corrupt[35] ^= 1;
    assert.throws(() => validateFile(corrupt, `a.${ext}`, mime));
  });
}
test('truncated OLE, PNG/JPEG signatures and fake Office ZIP are insufficient', () => {
  for (const [name,bytes,mime] of [['x.doc',Buffer.from('d0cf11e0a1b11ae1','hex'),'application/msword'],
    ['x.xls',pdf,'application/vnd.ms-excel'], ['x.docx',Buffer.from([80,75,3,4]),'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
    ['x.png',Buffer.from('89504e470d0a1a0a','hex'),'image/png'], ['x.jpg',Buffer.from([255,216,255,217]),'image/jpeg']]) {
    assert.throws(() => validateFile(bytes,name,mime));
  }
});
function legacy(type) {
  const b=Buffer.alloc(512*11); Buffer.from('d0cf11e0a1b11ae1','hex').copy(b);
  b.writeUInt16LE(0xfffe,28);b.writeUInt16LE(9,30);b.writeUInt16LE(6,32);b.writeUInt32LE(1,44);b.writeUInt32LE(1,48);
  b.writeUInt32LE(0xfffffffe,60);b.writeUInt32LE(0,72);b.writeUInt32LE(0,76);
  for(let i=0;i<128;i++) b.writeUInt32LE(0xffffffff,512+i*4);
  b.writeUInt32LE(0xfffffffd,512);b.writeUInt32LE(0xfffffffe,516);
  for(let i=2;i<=9;i++) b.writeUInt32LE(i===9?0xfffffffe:i+1,512+i*4);
  const entry=(offset,name,kind,start,size)=>{Buffer.from(name+'\0','utf16le').copy(b,offset);b.writeUInt16LE((name.length+1)*2,offset+64);b[offset+66]=kind;b.writeUInt32LE(start,offset+116);b.writeBigUInt64LE(BigInt(size),offset+120);};
  entry(1024,'Root Entry',5,0xfffffffe,0);entry(1152,type==='doc'?'WordDocument':'Workbook',2,2,4096);
  if(type==='doc') b.writeUInt16LE(0xa5ec,1536); else {b.writeUInt16LE(0x0809,1536);b.writeUInt16LE(8,1538);b.writeUInt16LE(0x0600,1540);b.writeUInt16LE(0x0005,1542);}
  return b;
}
for(const [ext,mime] of [['doc','application/msword'],['xls','application/vnd.ms-excel']]) {
  test(`${ext} validates compound directory and main stream, not OLE signature alone`,()=>{
    assert.equal(validateFile(legacy(ext),`a.${ext}`,mime),mime);
    assert.throws(()=>validateFile(legacy(ext==='doc'?'xls':'doc'),`a.${ext}`,mime));
  });
}
test('valid bounded PNG passes CRC/dimension checks; corrupt image fails',()=>{
  const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1cAAAAASUVORK5CYII=','base64');
  // Construct a CRC-valid minimal PNG from the same known small IDAT stream.
  for(let offset=8;offset+12<=png.length;){const size=png.readUInt32BE(offset);png.writeUInt32BE(crc(png.subarray(offset+4,offset+8+size)),offset+8+size);offset+=12+size;}
  assert.equal(validateFile(png,'a.png','image/png'),'image/png');
  png[20]^=1;assert.throws(()=>validateFile(png,'a.png','image/png'));
});
test('real scanner adapter fails closed when signatures/infrastructure unavailable', async () => {
  await assert.rejects(clamScanner({ socket: 'nonexistent', database: 'nonexistent' })(pdf));
});
for (const verdict of ['approved','rejected','outage']) {
  test(`test-only injected scanner ${verdict}; only approved mock is accepted`, async () => {
    const server = scannerServer({ secret: 'test-only', scan: async () => {
      if (verdict === 'outage') throw Error('offline');
      return { verdict, engine: 'MOCK-NOT-MALWARE-SCANNING' };
    } });
    await new Promise(r => server.listen(0, '127.0.0.1', r));
    try {
      const url = `http://127.0.0.1:${server.address().port}/scan`;
      const response = await fetch(url, { method:'POST',body:pdf,headers:{Authorization:'Bearer test-only','x-file-name':'a.pdf','x-file-mime':'application/pdf'} });
      assert.equal(response.status, verdict === 'outage' ? 503 : 200);
      const result = await response.json();
      if (verdict !== 'outage') { assert.equal(result.verdict,verdict); assert.equal(result.sha256,createHash('sha256').update(pdf).digest('hex')); }
      assert.equal((await fetch(url,{method:'POST',body:pdf})).status,401);
    } finally { await new Promise(r => server.close(r)); }
  });
}
test('integrity mismatch rejects without calling scanner or creating final bytes', async()=>{
  const f=fixture(); f.row.expected_sha256='0'.repeat(64);
  f.deps.scan=async()=>{throw Error('must not scan mismatched bytes');};
  await f.run('upload');assert.equal((await f.run('scan')).status,200);
  assert.equal(f.row.state,'rejected');assert.equal(f.objects.has(`${paths(f.row)}file`),false);
});
test('cleanup preserves committed final file and only deletes expired file when requested by SQL',async()=>{
  const f=fixture(), removed=[];f.deps.authorizeCleanup=async()=>{};
  f.deps.remove=async names=>removed.push(...names);
  f.deps.serviceRpc=async name=> name==='claim_expired_chat_attachments_v2'?
    [{attachment_id:id(1),storage_path:`${paths(f.row)}file`,size_bytes:pdf.length,chunks_only:true}]:null;
  assert.equal((await f.run('cleanup')).status,200);
  assert.deepEqual(removed,[`${paths(f.row)}part.0`]);
});
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
function fixture(verdict = 'approved') {
  const row = {attachment_id:id(1),conversation_id:id(2),sender_id:id(3),size_bytes:pdf.length,
    original_name:'a.pdf',mime_type:'application/pdf',state:'pending',can_upload:true,
    expected_sha256:createHash('sha256').update(pdf).digest('hex')};
  const objects = new Map(), calls = [];
  const deps = {enabled:true,origin:'http://local.test',authenticate:async () => {}, authorizeCleanup:async () => { throw Error('unauthorized'); },
    userRpc:async (_,name) => {calls.push(name); if (name === 'prepare_chat_attachment_scan_v2') {row.state='scanning'; return {...row,scan_token:id(4)};} return {...row};},
    serviceRpc:async (name,args) => {calls.push(name); if (name === 'finish_chat_attachment_scan_v2') row.state=args.p_verdict;},
    putImmutable:async (path,bytes) => { if(objects.has(path) && await sha256(objects.get(path)) !== await sha256(bytes)) throw Error('conflict'); objects.set(path,bytes); },
    download:async path => { if(!objects.has(path)) throw Error('missing'); return objects.get(path); },
    scan:async bytes => {if(verdict === 'outage') throw Error('offline'); return {verdict,engine:'MOCK-NOT-SCANNING',sha256:await sha256(bytes),size_bytes:bytes.length,mime_type:row.mime_type};},
  };
  const run = (op,body=pdf,index='0') => attachmentHandler(deps)(new Request(`http://local.test/function?op=${op}`,{method:'POST',body,headers:{origin:deps.origin,'x-attachment-id':id(1),'x-chunk-index':index}}));
  return {row,objects,calls,deps,run};
}
test('chunk bounds, exact final chunk, path validation', () => {
  assert.equal(chunkLength(CHUNK_BYTES+1,1),1);
  for (const [size,index] of [[0,0],[MAX+1,0],[1,-1],[1,1]]) assert.throws(() => chunkLength(size,index));
  assert.throws(() => paths({ attachment_id:'../x' }));
});
test('disabled, unauthorized and foreign origin never touch private storage', async () => {
  const f = fixture(); f.deps.enabled=false;
  assert.equal((await f.run('upload')).status,503); assert.equal(f.objects.size,0);
  f.deps.enabled=true; f.deps.authenticate=async () => {throw Error('unauthorized');};
  assert.equal((await f.run('upload')).status,503); assert.equal(f.objects.size,0);
  f.deps.origin='http://other.test';
  const request = new Request('http://local.test/?op=upload',{method:'POST',body:pdf,headers:{origin:'http://local.test'}});
  assert.equal((await attachmentHandler(f.deps)(request)).status,503);
});
test('chunk replay is identical; different bytes conflict; no message commit in uploader', async () => {
  const f = fixture();
  assert.equal((await f.run('upload')).status,200); assert.equal((await f.run('upload')).status,200); assert.equal(f.objects.size,1);
  const changed = Buffer.from(pdf); changed[10] ^= 1;
  assert.equal((await f.run('upload',changed)).status,503);
  assert.equal(f.calls.includes('send_chat_message'),false); assert.equal(f.calls.includes('send_chat_attachment_v2'),false);
});
for (const verdict of ['approved','rejected','outage']) {
  test(`quarantine ${verdict} cannot become a committed message in upload handler`, async () => {
    const f = fixture(verdict); await f.run('upload'); const response = await f.run('scan');
    assert.equal(response.status,verdict === 'outage' ? 503 : 200);
    assert.equal(f.row.state,verdict === 'outage' ? 'scanning' : verdict);
    assert.equal(f.objects.has(`${paths(f.row)}file`),verdict === 'approved');
    assert.equal(f.calls.some(x=>x.startsWith('send_')),false);
  });
}
