// Testable preflight. Caller supplies the only explicitly authorized public start.
export async function recordThenStream(obs,startStream){
  const owned=!(await obs.call('GetRecordStatus')).outputActive;
  try{
    if(owned)await obs.call('StartRecord');
    let ready=false;
    for(let i=0;i<12;i++){
      const [r,v]=await Promise.all([obs.call('GetRecordStatus'),obs.call('CallVendorRequest',{vendorName:'aitum-vertical-canvas',requestType:'status'})]);
      if(r.outputActive&&v.responseData.recording){ready=true;break;}
      await new Promise(r=>setTimeout(r,250));
    }
    if(!ready)throw Error('No se pudo confirmar la grabación de ambos formatos. No se inició el vivo.');
    await startStream();
  }catch(e){if(owned&&((await obs.call('GetRecordStatus')).outputActive))await obs.call('StopRecord');throw e;}
}
