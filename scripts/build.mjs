import {spawnSync} from 'node:child_process';
import {copyFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const result=spawnSync('moon',['build','--target','js','--release'],{cwd:root,stdio:'inherit'});
if(result.error||result.status!==0){console.error(result.error?.message??'MoonBit build failed');process.exit(result.status||2);}
mkdirSync(new URL('../web/',import.meta.url),{recursive:true});
copyFileSync(new URL('../_build/js/release/build/rename_plan.js',import.meta.url),new URL('../web/engine.js',import.meta.url));
console.log('Built MoonBit library → web/engine.js');
