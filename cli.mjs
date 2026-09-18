#!/usr/bin/env node
import {readFileSync,readdirSync,lstatSync,openSync,readSync,closeSync,fstatSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {plan_json,recover_json,journal_json} from './web/engine.js';
const limit=2*1024*1024;
function readJSON(path){const bytes=readFileSync(path);if(bytes.length>limit)throw Error('JSON input exceeds 2 MiB');return new TextDecoder('utf-8',{fatal:true}).decode(bytes);}
function snapshot(dir){
 const root=resolve(dir),names=readdirSync(root).sort();
 if(names.length>1000)throw Error('Directory limit: 1000 entries');
 return names.map(name=>{
  const path=join(root,name),before=lstatSync(path,{bigint:true});
  if(!before.isFile()||before.isSymbolicLink())throw Error(`Only flat regular-file directories are supported: ${name}`);
  if(before.size>64n*1024n*1024n)throw Error(`File exceeds snapshot limit of 64 MiB: ${name}`);
  const fd=openSync(path,'r');
  try{
   const opened=fstatSync(fd,{bigint:true});
   if(!opened.isFile()||opened.dev!==before.dev||opened.ino!==before.ino)throw Error(`File changed during scan: ${name}`);
   const hash=createHash('sha256'),buffer=Buffer.alloc(64*1024);let bytes=0,count;
   while((count=readSync(fd,buffer,0,buffer.length,null))>0){bytes+=count;if(bytes>64*1024*1024)throw Error(`File grew during scan: ${name}`);hash.update(buffer.subarray(0,count));}
   const after=fstatSync(fd,{bigint:true}),named=lstatSync(path,{bigint:true});
   if(after.size!==before.size||after.mtimeNs!==before.mtimeNs||named.ino!==before.ino||named.dev!==before.dev||named.isSymbolicLink())throw Error(`File changed during scan: ${name}`);
   return {name,identity:'sha256:'+hash.digest('hex')};
  }finally{closeSync(fd);}
 });
}
function main(){
 const [command,...args]=process.argv.slice(2);
 if(command==='--help'||!command){console.log('MoonRename Plan\n  snapshot <directory>\n  plan <request.json>\n  simulate <request.json> <completed-count>\n  recover <request.json> <observed-snapshot.json>\n  reconcile <request.json> <journal.json> <observed-snapshot.json>\nOutput goes to stdout. Exit 0: ready/matched; 1: blocked/diverged/ambiguous; 2: invalid input/IO.\nRead-only: no file is renamed, written or deleted.');return command?0:2;}
 let result;
 if(command==='snapshot'&&args.length===1) result=snapshot(args[0]);
 else if(command==='reconcile'&&args.length===3)result=JSON.parse(journal_json(readJSON(args[0]),readJSON(args[1]),readJSON(args[2])));
 else if(command==='plan'&&args.length===1)result=JSON.parse(plan_json(readJSON(args[0])));
 else if(command==='simulate'&&args.length===2){
  if(!/^(0|[1-9][0-9]*)$/.test(args[1]))throw Error('completed-count must be a nonnegative integer');
  const request=JSON.parse(readJSON(args[0]));request.completed=Number(args[1]);result=JSON.parse(plan_json(JSON.stringify(request)));
 }else if(command==='recover'&&args.length===2)result=JSON.parse(recover_json(readJSON(args[0]),readJSON(args[1])));
 else throw Error('Unknown command or wrong argument count; use --help');
 console.log(JSON.stringify(result,null,2));
 return result.status==='error'?2:['blocked','diverged','ambiguous','invalid-journal'].includes(result.status)?1:0;
}
try{process.exitCode=main();}catch(error){console.error(error.message);process.exitCode=2;}
