// Local, read-only comparison of complete Supabase JSON or CSV result exports.
// No package dependency, network, database or field-size limit imposed here.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
export function csvRows(text) {
 const rows=[];let row=[],field='',quoted=false,closed=false;
 for(let i=0;i<text.length;i++){
  const c=text[i];
  if(quoted){if(c==='"'){if(text[i+1]==='"'){field+='"';i++;}else{quoted=false;closed=true;}}else field+=c;continue;}
  if(c==='"'){if(field||closed)throw Error('Malformed CSV quote');quoted=true;}
  else if(c===','){row.push(field);field='';closed=false;}
  else if(c==='\r'||c==='\n'){if(c==='\r'&&text[i+1]==='\n')i++;row.push(field);rows.push(row);row=[];field='';closed=false;}
  else{if(closed)throw Error('Unexpected text after quoted CSV field');field+=c;}
 }
 if(quoted)throw Error('Truncated quoted CSV');
 if(field||row.length||closed){row.push(field);rows.push(row);}
 return rows;
}
const expectedAbsences=['no_basic_relations','no_basic_routines','no_basic_policies','no_basic_bucket','no_basic_binding_key'];
export function parseBaseline(input){
 const text=input.replace(/^\uFEFF/,'').trim();let result;
 if(text.startsWith('{')||text.startsWith('[')){
  result=JSON.parse(text);if(Array.isArray(result)){assert.equal(result.length,1,'Exactly one result row required');result=result[0];}
 }else{
  const rows=csvRows(text);assert.equal(rows.length,2,'Exactly one CSV data row required');
  assert.equal(rows[0].length,rows[1].length,'CSV field count');
  assert.equal(new Set(rows[0]).size,rows[0].length,'Duplicate CSV header');
  result=Object.fromEntries(rows[0].map((key,i)=>[key,rows[1][i]]));
 }
 const baseline=typeof result.baseline==='string'?JSON.parse(result.baseline):result.baseline;
 assert.ok(Array.isArray(baseline),'Complete baseline JSON array required');
 assert.equal(Number(result.record_count),baseline.length,'Array length must equal record_count');
 const map=new Map();
 for(const item of baseline){
  assert.equal(typeof item.category,'string');assert.equal(typeof item.object_identity,'string');assert.equal(typeof item.fingerprint_or_value,'string');
  const key=JSON.stringify([item.category,item.object_identity]);assert.ok(!map.has(key),`Duplicate key ${key}`);map.set(key,item.fingerprint_or_value);
 }
 assert.equal(Number(result.unique_key_count),map.size,'unique_key_count');
 assert.match(result.baseline_md5??'',/^[0-9a-f]{32}$/,'Database digest required');
 const absences=typeof result.absence_checks==='string'?JSON.parse(result.absence_checks):result.absence_checks;
 for(const key of expectedAbsences){assert.equal(absences?.[key],'PASS',key);assert.equal(map.get(JSON.stringify(['absence',key])),'PASS',key);}
 const context=JSON.parse(map.get(JSON.stringify(['context','inspection']))??'null');
 assert.equal(context?.role,'postgres');assert.equal(context?.database,'postgres');assert.match(context?.version??'',/^17\.11(?:\s|$)/);
 assert.equal(context?.replication_role,'origin');assert.equal(typeof context?.search_path,'string');
 return{map,result,context};
}
function compare(before,after){
 const changes=[];
 for(const key of new Set([...before.map.keys(),...after.map.keys()])) if(before.map.get(key)!==after.map.get(key)) changes.push(JSON.parse(key));
 assert.equal(before.result.baseline_md5,after.result.baseline_md5,'Database digest differs');
 assert.equal(changes.length,0,`Catalogue differences (first 20 keys): ${JSON.stringify(changes.slice(0,20))}`);
 return before.map.size;
}
if(process.argv[2]==='--self-test'){
 const rows=[...expectedAbsences.map(key=>({category:'absence',object_identity:key,fingerprint_or_value:'PASS'})),
  {category:'context',object_identity:'inspection',fingerprint_or_value:JSON.stringify({role:'postgres',database:'postgres',version:'17.11',search_path:'"$user", public',replication_role:'origin'})},
  {category:'routine',object_identity:'public.test(text)',fingerprint_or_value:'quoted,"comma"\nand newline'}];
 const value={record_count:rows.length,unique_key_count:rows.length,baseline_md5:'a'.repeat(32),absence_checks:Object.fromEntries(expectedAbsences.map(k=>[k,'PASS'])),baseline:rows};
 const quote=v=>'"'+String(v).replaceAll('"','""')+'"';
 const csv=Object.keys(value).join(',')+'\r\n'+Object.values(value).map(v=>quote(typeof v==='object'?JSON.stringify(v):v)).join(',')+'\r\n';
 assert.equal(compare(parseBaseline(JSON.stringify([value])),parseBaseline(csv)),rows.length);
 assert.throws(()=>csvRows('a\n"unterminated'));
 assert.throws(()=>parseBaseline(JSON.stringify({...value,baseline:[...rows,rows[0]],record_count:rows.length+1})));
 assert.throws(()=>parseBaseline(csv.replace('PASS','FAIL')));
 console.log('PASS: quoted CSV/JSON equivalence, embedded comma/quote/newline, complete row/count/key validation, duplicate/truncation/absence rejection. Synthetic data only.');
}else if(process.argv.length===4){
 try{
  const contents=process.argv.slice(2).map(path=>readFileSync(path));
  const parsed=contents.map(bytes=>parseBaseline(bytes.toString('utf8')));
  console.log(JSON.stringify({result:'PASS',compared_keys:compare(...parsed),all_five_absences:'PASS',
   original_file_sha256:contents.map(bytes=>createHash('sha256').update(bytes).digest('hex')),context:parsed[0].context},null,2));
 }catch(error){console.error(`FAIL: ${error.message}`);process.exitCode=1;}
}else{console.error('Usage: node tools/chat_basic/compare_baselines.mjs <before.json-or-csv> <after.json-or-csv>');process.exitCode=1;}
