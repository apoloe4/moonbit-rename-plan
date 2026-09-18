import {performance} from 'node:perf_hooks';
import {plan_json,recover_json} from '../web/engine.js';
const results=[];
for(const count of [10,100,500,1000]){
 const request={entries:Array.from({length:count},(_,i)=>({name:`file-${i}`,identity:`id-${i}`})),mappings:Array.from({length:count},(_,i)=>({source:`file-${i}`,target:`file-${(i+1)%count}`}))};
 const start=performance.now(),plan=JSON.parse(plan_json(JSON.stringify(request))),planned=performance.now();
 const simulated=JSON.parse(plan_json(JSON.stringify({...request,completed:Math.floor(plan.steps.length/2)})));
 const recoveryStart=performance.now(),recovery=JSON.parse(recover_json(JSON.stringify(request),JSON.stringify(simulated.simulation.snapshot))),end=performance.now();
 if(plan.status!=='ready'||recovery.matchingPrefixes.length!==1)throw Error('Benchmark correctness check failed');
 results.push({entries:count,steps:plan.stepCount,planMilliseconds:+(planned-start).toFixed(2),recoveryMilliseconds:+(end-recoveryStart).toFixed(2)});
}
console.log(JSON.stringify({node:process.version,platform:process.platform,results,note:'Single local run; includes JSON parsing/rendering. Not a performance guarantee.'},null,2));
