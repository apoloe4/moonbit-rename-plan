const $=id=>document.getElementById(id);
export function toMappings(entries,targets){return entries.map((e,i)=>({source:e.name,target:targets[i]??e.name}));}
export function validateFiles(files){
 if(!files.length)throw Error('请选择文件。');
 if(files.length>1000)throw Error('最多选择 1000 个文件。');
 const names=new Set();let total=0;
 for(const file of files){
  if(names.has(file.name))throw Error(`存在同名文件：${file.name}。请选择同一个文件夹。`);
  names.add(file.name);total+=file.size;
  if(file.size>64*1024*1024)throw Error(`文件超过 64 MiB：${file.name}`);
 }
 if(total>128*1024*1024)throw Error('所选文件合计不能超过 128 MiB，请使用 CLI 快照。');
}
export function initEditor(){
 let entries=[],targets=[],ticket=0;
 const fields=['prefix','suffix','find','replacement','onlySuffix','caseMode','sequenceStart','sequenceWidth','extension'];
 function unlock(){for(const id of ['file-list','rule-form'])$(id).inert=false;$('edit-mode').disabled=$('name-policy').disabled=false;}
 function sync(){
  const req={entries,policy:$('name-policy').value};
  if($('edit-mode').value==='manual')req.mappings=toMappings(entries,targets);
  else{
   req.rule={};for(const key of ['prefix','suffix','find','replacement','onlySuffix','caseMode'])req.rule[key]=$('rule-'+key).value;
   if($('numbering').checked){req.rule.sequenceStart=Number($('rule-sequenceStart').value);req.rule.sequenceWidth=Number($('rule-sequenceWidth').value);}
   if($('change-extension').checked)req.rule.extension=$('rule-extension').value;
  }
  $('request').value=JSON.stringify(req,null,2);$('request').dispatchEvent(new Event('input'));
 }
 function draw(){
  const rule=$('edit-mode').value==='rule';$('rule-form').hidden=!rule;
  const list=$('file-list');list.replaceChildren();
  const caption=document.createElement('p');caption.className='hint';caption.textContent=`${entries.length} 个文件 · ${rule?'规则将由 MoonBit 核心展开':'未改动的目标名称保持原样'}`;list.append(caption);
  entries.forEach((entry,i)=>{
   const row=document.createElement('label');row.className='file-row';const name=document.createElement('span');name.textContent=entry.name;row.append(name);
   if(!rule){const input=document.createElement('input');input.value=targets[i];input.setAttribute('aria-label',`目标名称：${entry.name}`);input.oninput=()=>{targets[i]=input.value;sync();};row.append(input);}
   list.append(row);
  });
 }
 function load(){
  ticket++;
  try{
   const req=JSON.parse($('request').value);
   if(!Array.isArray(req.entries)||req.entries.length>1000||!req.entries.every(e=>typeof e.name==='string'&&typeof e.identity==='string'))throw Error('表单需要 entries 数组，每项包含 name 和 identity，最多 1000 项。');
   entries=req.entries;const map=new Map((req.mappings??[]).map(m=>[m.source,m.target]));targets=entries.map(e=>map.get(e.name)??e.name);
   $('name-policy').value=req.policy??'exact';$('edit-mode').value=req.rule?'rule':'manual';
   for(const key of fields)$('rule-'+key).value=req.rule?.[key]??({caseMode:'keep',sequenceStart:1,sequenceWidth:3}[key]??'');
   unlock();$('numbering').checked=req.rule?.sequenceStart!=null;$('change-extension').checked=req.rule?.extension!=null;draw();
   $('import-status').textContent='已载入表单；可直接编辑名称或切换批量规则。';
  }catch(e){$('import-status').textContent=e.message;}
 }
 $('request').addEventListener('change',load);
 $('request').addEventListener('input',()=>{ticket++;if(document.activeElement===$('request')){for(const id of ['file-list','rule-form'])$(id).inert=true;$('edit-mode').disabled=$('name-policy').disabled=true;$('import-status').textContent='JSON 已修改，点击“将 JSON 载入表单”后再使用表单。';}});
 $('apply-json').onclick=()=>{load();$('request').dispatchEvent(new Event('input'));};
 $('edit-mode').onchange=()=>{draw();sync();};$('name-policy').onchange=sync;
 for(const key of fields)$('rule-'+key).oninput=sync;
 $('numbering').onchange=sync;$('change-extension').onchange=sync;
 $('files').onchange=async()=>{
  const files=Array.from($('files').files),id=++ticket;
  if(!files.length)return;
  try{
   validateFiles(files);const imported=[];
   for(const [i,file] of files.entries()){
    $('import-status').textContent=`正在本地读取 ${i+1}/${files.length}：${file.name}`;
    const digest=await crypto.subtle.digest('SHA-256',await file.arrayBuffer());
    if(id!==ticket)return;
    imported.push({name:file.name,identity:'sha256:'+Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('')});
   }
   unlock();entries=imported;targets=entries.map(e=>e.name);$('edit-mode').value='manual';draw();sync();
   $('import-status').textContent=`已读取 ${entries.length} 个文件，内容未上传。编辑右侧目标名称，再生成预览。`;
  }catch(e){if(id===ticket)$('import-status').textContent=e.message;}
  finally{$('files').value='';}
 };
 load();
}
