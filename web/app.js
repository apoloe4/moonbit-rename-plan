import {samples} from './samples.js';
const $=id=>document.getElementById(id);
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let plan=null,simulation=null,worker=null,serial=0;
const notify=(message,kind='')=>{$('notice').textContent=message;$('notice').className=kind;};
function invalidate(){
 serial++;worker?.terminate();worker=null;plan=simulation=null;
 for(const id of ['export-json','export-md','export-dot','boundary','recover','use-snapshot'])$(id).disabled=true;
 $('run').disabled=false;for(const id of ['steps-count','temp-count','skip-count'])$(id).textContent='—';
 $('steps').replaceChildren();$('components').replaceChildren();$('problems').replaceChildren();$('step-note').textContent='';$('snapshot').textContent=$('rollback').textContent='—';$('recovery').textContent='输入已变化，请重新生成计划。';
}
function request(kind,completed=0){
 serial++;worker?.terminate();const id=serial;
 try{
  if(new TextEncoder().encode($('request').value).length>2*1024*1024||new TextEncoder().encode($('observed').value).length>2*1024*1024)throw Error('每个 JSON 输入最多 2 MiB。');
  const input=JSON.parse($('request').value);if(kind==='plan')input.completed=completed;
  worker=new Worker(new URL('./worker.js',import.meta.url),{type:'module'});
  $('run').disabled=true;notify('MoonBit 正在分析…');
  worker.onmessage=({data})=>{
   if(data.id!==serial)return;worker.terminate();worker=null;$('run').disabled=false;
   if(data.result.status==='error'){notify(data.result.message,'error');return;}
   if(kind==='plan')render(data.result);else renderRecovery(data.result);
  };
  worker.onerror=()=>{if(id!==serial)return;invalidate();notify('核心加载失败，请通过 npm start 打开页面。','error');};
  worker.postMessage({id,kind,request:JSON.stringify(input),observed:$('observed').value});
 }catch(error){$('run').disabled=false;notify(error.message,'error');}
}
function render(result){
 plan=result;simulation=result.simulation??null;
 $('recovery').textContent=result.status==='ready'?'可使用当前模拟快照，或粘贴现场快照进行分析。':'请先解决计划中的冲突。';
 $('steps-count').textContent=result.stepCount;$('temp-count').textContent=result.temporaryNames.length;$('skip-count').textContent=result.skipped;
 $('problems').textContent=result.problems.map(p=>`${p.code} · ${p.name}：${p.detail}`).join('\n');
 $('components').innerHTML=result.components.map(c=>`<span>${escape(c.kind)} · ${c.sources.length} 个名称</span>`).join('');
 const completed=simulation?.completed??0;
 $('steps').innerHTML=result.steps.slice(0,250).map(s=>`<li class="${s.index<completed?'done':''}"><span class="num">${s.index+1}</span><span class="route">${escape(s.source)}<em>→</em>${escape(s.target)}</span><span class="reason">${escape({park:'暂存',direct:'移动',release:'就位'}[s.reason]??s.reason)}</span></li>`).join('')||'<li class="placeholder">'+(result.status==='blocked'?'存在冲突，未生成操作序列。':'无需改名。')+'</li>';
 $('step-note').textContent=result.steps.length>250?'展示前 250 步；导出包含完整计划。':'步骤必须按顺序执行，每一步都要求目标名称未被占用。';
 for(const id of ['export-json','export-md','export-dot'])$(id).disabled=false;
 const ready=result.status==='ready';for(const id of ['boundary','recover','use-snapshot'])$(id).disabled=!ready;
 $('boundary').max=result.stepCount;$('boundary').value=completed;$('boundary-label').textContent=`已完成 ${completed} / ${result.stepCount} 步`;
 $('snapshot').textContent=simulation?simulation.snapshot.map(e=>`${e.name}  [${e.identity}]`).join('\n'):'—';
 $('rollback').textContent=simulation?(simulation.rollback.map(s=>`${s.source} → ${s.target}`).join('\n')||'尚未执行，无需回退。'):'—';
 notify(ready?`计划可用：${result.stepCount} 步，${result.temporaryNames.length} 个临时名称。这里只生成方案，不修改磁盘。`:`发现 ${result.problems.length} 个冲突，请先调整输入。`,ready?'ready':'error');
}
function renderRecovery(result){
 const labels={resumable:'找到唯一进度，可以继续或回退',complete:'与最终状态一致',ambiguous:'存在多个可能进度，不能自动决定',diverged:'现场偏离计划，不能继续或回退'};
 $('recovery').textContent=[labels[result.status]??result.status,`匹配已完成步数：${result.matchingPrefixes?.join(', ')||'无'}`,result.differences?.length?'差异：\n'+result.differences.map(d=>`${d.kind} · ${d.name} (${d.expected} → ${d.observed})`).join('\n'):'',result.continueSteps?.length?'继续：\n'+result.continueSteps.map(s=>`${s.source} → ${s.target}`).join('\n'):'',result.rollback?.length?'回退：\n'+result.rollback.map(s=>`${s.source} → ${s.target}`).join('\n'):''].filter(Boolean).join('\n\n');
 notify('现场恢复分析完成。',result.status==='diverged'||result.status==='ambiguous'?'error':'ready');
}
function loadSample(){invalidate();$('request').value=JSON.stringify(samples[$('sample').value],null,2);$('observed').value='';request('plan');}
$('request').oninput=()=>{invalidate();notify('输入已修改，请重新生成计划。');};
$('observed').oninput=()=>{$('recovery').textContent='现场快照已修改，请重新分析。';if(worker){serial++;worker.terminate();worker=null;$('run').disabled=false;}};
$('load-sample').onclick=loadSample;$('run').onclick=()=>{invalidate();request('plan');};
$('boundary').oninput=()=>request('plan',Number($('boundary').value));
$('use-snapshot').onclick=()=>{if(simulation){$('observed').value=JSON.stringify(simulation.snapshot,null,2);request('recover');}};
$('recover').onclick=()=>request('recover');
function download(content,type,filename){const url=URL.createObjectURL(new Blob([content],{type}));const a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
$('export-json').onclick=()=>plan&&download(JSON.stringify(plan,null,2),'application/json','moonrename-plan.json');
$('export-md').onclick=()=>plan&&download(plan.markdown,'text/markdown','moonrename-plan.md');
$('export-dot').onclick=()=>plan&&download(plan.dot,'text/plain','moonrename-plan.dot');
loadSample();

