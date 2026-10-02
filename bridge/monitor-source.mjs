import {randomUUID} from 'node:crypto';
export function validMonitorSource(name) {
  return typeof name === 'string' && name.length < 256 && /^[^\r\n]+ \(Anima Studio Monitor\)$/.test(name);
}
// DistroAV receives frames only while a source is "showing". Probe disabled
// first, move fully off-canvas, then enable. Never expose the probe on-screen.
export async function probeMonitor(o,name) {
  const {currentProgramSceneName:sceneName}=await o.call('GetCurrentProgramScene');
  const inputName='MONITOR CHECK '+randomUUID();
  let input=false;
  try {
    const item=await o.call('CreateInput',{sceneName,inputName,inputKind:'ndi_source',inputSettings:{ndi_source_name:name,ndi_audio:false,ndi_behavior:0,ndi_framesync:true},sceneItemEnabled:false});input=true;
    const target={sceneName,sceneItemId:item.sceneItemId};
    await o.call('SetSceneItemTransform',{...target,sceneItemTransform:{positionX:80000,positionY:80000}});
    await o.call('SetSceneItemEnabled',{...target,sceneItemEnabled:true});
    for(let n=0;n<20;n++) {
      const t=(await o.call('GetSceneItemTransform',{sceneName,sceneItemId:item.sceneItemId})).sceneItemTransform;
      if(t.sourceWidth>0&&t.sourceHeight>0)return;
      await new Promise(r=>setTimeout(r,250));
    }
    throw Error('servidor no recibió imagen del monitor. Se conserva la pantalla anterior.');
  } finally {
    if(input)await o.call('RemoveInput',{inputName}).catch(()=>{});
  }
}
export async function selectMonitorSource(o, name, inputName = 'Screen') {
  if (!validMonitorSource(name)) throw Error('Fuente de monitor inválida.');
  const before = await o.call('GetInputSettings', {inputName});
  if (before.inputKind !== 'ndi_source') throw Error('La pantalla no es una fuente NDI; no se modificó.');
  if(before.inputSettings.ndi_source_name!==name)await probeMonitor(o,name);
  await o.call('SetInputSettings',{inputName,inputSettings:{ndi_source_name:name,ndi_audio:false},overlay:true});
  try {
    const after=await o.call('GetInputSettings',{inputName});
    if(after.inputSettings.ndi_source_name!==name)throw Error('No se confirmó la selección.');
  } catch(e) {
    await o.call('SetInputSettings',{inputName,inputSettings:before.inputSettings,overlay:false});
    throw e;
  }
}
