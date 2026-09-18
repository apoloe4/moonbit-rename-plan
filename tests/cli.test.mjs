import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {plan_json,recover_json} from '../web/engine.js';
const root=fileURLToPath(new URL('../',import.meta.url));
const run=(...args)=>spawnSync(process.execPath,['cli.mjs',...args],{cwd:root,encoding:'utf8'});
const read=name=>readFileSync(new URL('../examples/'+name+'.json',import.meta.url),'utf8');
test('CLI swap has three operations and one temporary name',()=>{
 const result=run('plan','examples/swap.json');assert.equal(result.status,0);
 const p=JSON.parse(result.stdout);assert.equal(p.stepCount,3);assert.equal(p.temporaryNames.length,1);assert.equal(p.audit.valid,true);
});
test('CLI blocked request exits 1 without steps',()=>{
 const result=run('plan','examples/blocked.json');assert.equal(result.status,1);assert.deepEqual(JSON.parse(result.stdout).steps,[]);
});
test('CLI simulated prefix and snapshot recovery agree',()=>{
 const result=run('simulate','examples/swap.json','1');assert.equal(result.status,0);
 const sim=JSON.parse(result.stdout).simulation;assert.deepEqual(sim.snapshot,JSON.parse(read('interrupted')));
 const recovery=run('recover','examples/swap.json','examples/interrupted.json');assert.equal(recovery.status,0);assert.deepEqual(JSON.parse(recovery.stdout).matchingPrefixes,[1]);
});
test('changed identity blocks recovery',()=>{
 const result=run('recover','examples/swap.json','examples/diverged.json');assert.equal(result.status,1);assert.equal(JSON.parse(result.stdout).status,'diverged');
});
test('equal identities remain ambiguous without trusted checkpoint',()=>{
 const request=JSON.parse(read('ambiguous'));const result=JSON.parse(recover_json(JSON.stringify(request),JSON.stringify(request.entries)));
 assert.equal(result.status,'ambiguous');assert.deepEqual(result.continueSteps,[]);
});
test('snapshot hashes actual bytes and does not modify inputs',()=>{
 const dir=mkdtempSync(join(tmpdir(),'moonrename-snapshot-'));
 try{
  const bytes=Buffer.from([0,255,13,10,65]);writeFileSync(join(dir,'one.bin'),bytes);
  const result=run('snapshot',dir);assert.equal(result.status,0);assert.deepEqual(JSON.parse(result.stdout),[{name:'one.bin',identity:'sha256:'+createHash('sha256').update(bytes).digest('hex')}]);
  assert.deepEqual(readFileSync(join(dir,'one.bin')),bytes);
  mkdirSync(join(dir,'sub'));assert.equal(run('snapshot',dir).status,2);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
test('wrong commands, invalid counts and missing files exit 2',()=>{
 for(const args of [[],['apply','x'],['plan','missing.json'],['simulate','examples/swap.json','-1'],['simulate','examples/swap.json','1.5'],['simulate','examples/swap.json','99']]) assert.equal(run(...args).status,2,args.join(' '));
 assert.equal(run('--help').status,0);
});
test('all shipped ready examples pass audit and finish without clobbering',()=>{
 for(const name of ['swap','cycle','case_only','ambiguous','rule']){
  const p=JSON.parse(plan_json(read(name)));assert.equal(p.status,'ready',name);assert.equal(p.audit.valid,true);
  const state=new Map(p.initial.map(e=>[e.name,e.identity]));
  for(const s of p.steps){assert.equal(state.get(s.source),s.identity);assert.equal(state.has(s.target),false);state.delete(s.source);state.set(s.target,s.identity);assert.equal(state.size,p.initial.length);}
  assert.deepEqual([...state].sort(),p.desired.map(e=>[e.name,e.identity]).sort());
 }
});
test('seeded permutations satisfy an independent state-machine oracle',()=>{
 let seed=1729;const rand=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
 for(let trial=0;trial<80;trial++){
  const names=Array.from({length:2+rand(14)},(_,i)=>'file-'+i),targets=[...names];
  for(let i=targets.length-1;i>0;i--){const j=rand(i+1);[targets[i],targets[j]]=[targets[j],targets[i]];}
  const req={entries:names.map((name,i)=>({name,identity:'id-'+i})),mappings:names.map((source,i)=>({source,target:targets[i]}))};
  const p=JSON.parse(plan_json(JSON.stringify(req)));assert.equal(p.status,'ready');const state=new Map(req.entries.map(e=>[e.name,e.identity]));
  for(const s of p.steps){assert.equal(state.has(s.target),false);assert.equal(state.get(s.source),s.identity);state.delete(s.source);state.set(s.target,s.identity);}
  assert.deepEqual([...state].sort(),p.desired.map(e=>[e.name,e.identity]).sort());
  const completed=rand(p.steps.length+1),sim=JSON.parse(plan_json(JSON.stringify({...req,completed}))).simulation;
  const recovery=JSON.parse(recover_json(JSON.stringify(req),JSON.stringify(sim.snapshot)));assert.deepEqual(recovery.matchingPrefixes,[completed]);
 }
});

test('intent journal resolves operation completed before result was logged',()=>{
 const result=run('reconcile','examples/swap.json','examples/pending-journal.json','examples/interrupted.json');
 assert.equal(result.status,0);const value=JSON.parse(result.stdout);assert.equal(value.status,'acknowledge-pending');assert.equal(value.nextReceipt.event,'completed');assert.equal(value.observedCompleted,1);
});
