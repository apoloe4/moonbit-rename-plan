import {plan_json,recover_json} from './engine.js';
self.onmessage=({data})=>{
 try{self.postMessage({id:data.id,kind:data.kind,result:JSON.parse(data.kind==='recover'?recover_json(data.request,data.observed):plan_json(data.request))});}
 catch(error){self.postMessage({id:data.id,kind:data.kind,result:{status:'error',message:error.message}});}
};
