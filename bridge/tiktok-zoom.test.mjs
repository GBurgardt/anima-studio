import test from 'node:test';
import assert from 'node:assert/strict';
import {zoomCrop,zoomState,applyZoom,zoomTarget} from './tiktok-zoom.mjs';
const base={sourceWidth:1920,sourceHeight:1080,cropLeft:0,cropRight:0,cropTop:0,cropBottom:0};
test('zoom preserves aspect ratio, limits and reversible reset',()=>{
 let t={...base};
 for(let n=0;n<30;n++)t={...t,...zoomCrop(t,'in')};
 assert.equal(zoomState(t).factor,4);
 for(const a of ['left','right','up','down'])for(let n=0;n<30;n++){
   t={...t,...zoomCrop(t,a)};
   for(const k of ['cropLeft','cropRight','cropTop','cropBottom'])assert.ok(t[k]>=0);
   assert.equal(t.sourceWidth-t.cropLeft-t.cropRight,480);
   assert.equal(t.sourceHeight-t.cropTop-t.cropBottom,270);
 }
 assert.deepEqual(zoomCrop(t,'reset'),{cropLeft:0,cropRight:0,cropTop:0,cropBottom:0});
 assert.deepEqual(zoomCrop(base,'out'),zoomCrop(base,'reset'));
 assert.throws(()=>zoomCrop(base,'bad'));
 assert.throws(()=>zoomCrop({...base,sourceWidth:0},'in'));
});
test('only vertical scene item receives crop; no shared input or output writes',async()=>{
 let t={...base},writes=[];
 const o={call:async(method,args)=>{
   assert.equal(args.canvasUuid,zoomTarget.canvasUuid);
   assert.equal(args.sceneName,zoomTarget.sceneName);
   if(method==='GetSceneItemList')return {sceneItems:[{sourceName:'Screen',inputKind:'ndi_source',sceneItemId:6,sceneItemTransform:t}]};
   if(method==='SetSceneItemTransform'){writes.push(args);t={...t,...args.sceneItemTransform};return {};}
   if(method==='GetSceneItemTransform')return {sceneItemTransform:t};
   throw Error('unexpected operation');
 }};
 assert.equal((await applyZoom(o,'in')).factor,1.25);
 assert.equal(writes.length,1);
 assert.deepEqual(Object.keys(writes[0].sceneItemTransform).sort(),['cropBottom','cropLeft','cropRight','cropTop']);
});
