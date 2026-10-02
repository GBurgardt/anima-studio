import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
const dir=path.join(os.homedir(),'.config/anima-studio');
const template=JSON.parse(await fs.readFile(new URL('../Config/server.example.json',import.meta.url),'utf8'));
template.recordingDirectory=path.join(os.homedir(),'Movies/Anima');
await fs.mkdir(dir,{recursive:true,mode:0o700});
try{await fs.writeFile(path.join(dir,'server.json'),JSON.stringify(template,null,2)+'\n',{flag:'wx',mode:0o600});console.log('Created ~/.config/anima-studio/server.json. Add OBS password and map your scenes. Nothing was started.')}catch(e){if(e.code==='EEXIST')console.log('Configuration already exists; preserved unchanged.');else throw e}
