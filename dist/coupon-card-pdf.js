function* buildPdfSteps({codes,jpeg,width=1536,height=864}) {
 if(!Array.isArray(codes)||codes.length<1||codes.length>100000||codes.some(c=>typeof c!=='string'||!/^\d{10}$/.test(c))||new Set(codes).size!==codes.length)throw new Error('أكواد الكارتات غير صالحة');
 if(!(jpeg instanceof Uint8Array)||jpeg.length<4||jpeg[0]!==255||jpeg[1]!==216||!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)throw new Error('تعذّر قراءة قالب الكارت');
 const encoder=new TextEncoder(),ascii=s=>encoder.encode(s),pageWidth=160*72/25.4,pageHeight=pageWidth*height/width,scale=pageWidth/width;
 const objects=[null];const add=value=>{objects.push(value);return objects.length-1;};
 add(ascii('<< /Type /Catalog /Pages 2 0 R >>'));
 add(ascii(`<< /Type /Pages /Count ${codes.length} /Kids [${codes.map((_,i)=>`${5+i*2} 0 R`).join(' ')}] >>`));
 add([ascii(`<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`),jpeg,ascii('\nendstream')]);
 add(ascii('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'));
 let page=0;for(const code of codes){
  const fontSize=width*0.04167*scale,x=width*0.73385*scale-code.length*0.556*fontSize/2,y=height*0.207*scale-fontSize*0.359;
  const serial=String(page+1),serialFontSize=width*0.028*scale,serialX=width*0.0945*scale-serial.length*0.556*serialFontSize/2,serialY=height*0.883*scale-serialFontSize*0.359;
  const commands=`q ${pageWidth.toFixed(4)} 0 0 ${pageHeight.toFixed(4)} 0 0 cm /Template Do Q\nBT /Code ${fontSize.toFixed(4)} Tf 0.30 0.025 0.025 rg 1 0 0 1 ${x.toFixed(4)} ${y.toFixed(4)} Tm (${code}) Tj ET\nBT /Code ${serialFontSize.toFixed(4)} Tf 0.15 0.06 0.015 rg 1 0 0 1 ${serialX.toFixed(4)} ${serialY.toFixed(4)} Tm (${serial}) Tj ET\n`;
  const streamId=objects.length+1;
  add(ascii(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth.toFixed(4)} ${pageHeight.toFixed(4)}] /Resources << /XObject << /Template 3 0 R >> /Font << /Code 4 0 R >> >> /Contents ${streamId} 0 R >>`));
  add(ascii(`<< /Length ${ascii(commands).length} >>\nstream\n${commands}endstream`));if(++page%500===0)yield {page,total:codes.length};
 }
 const chunks=[ascii('%PDF-1.4\n')],offsets=[0];let length=chunks[0].length;
 const append=b=>{chunks.push(b);length+=b.length;};
 for(let i=1;i<objects.length;i++){offsets.push(length);append(ascii(`${i} 0 obj\n`));for(const b of Array.isArray(objects[i])?objects[i]:[objects[i]])append(b);append(ascii('\nendobj\n'));}
 const xref=length;append(ascii(`xref\n0 ${objects.length}\n0000000000 65535 f \n${offsets.slice(1).map(offset=>String(offset).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`));
 const bytes=new Uint8Array(length);let position=0;for(const chunk of chunks){bytes.set(chunk,position);position+=chunk.length;}return bytes;
}

export function buildCouponCardsPdf(options){const steps=buildPdfSteps(options);let result;do{result=steps.next();}while(!result.done);return result.value;}
export async function buildCouponCardsPdfAsync(options){const steps=buildPdfSteps(options);let result;do{result=steps.next();if(!result.done){options.onProgress?.(result.value);await new Promise(resolve=>setTimeout(resolve,0));}}while(!result.done);return result.value;}

let templatePromise;
export async function loadCouponTemplate() {
 if(templatePromise)return templatePromise;
 templatePromise=(async()=>{const img=new Image();img.src=new URL('./assets/free-ride-card.png?v=1.6.68',import.meta.url).href;await img.decode();const canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;const context=canvas.getContext('2d');if(!context)throw new Error('تعذّر تجهيز صورة الكارت');context.drawImage(img,0,0);const raw=atob(canvas.toDataURL('image/jpeg',0.96).split(',')[1]);return {jpeg:Uint8Array.from(raw,c=>c.charCodeAt(0)),width:canvas.width,height:canvas.height};})().catch(error=>{templatePromise=null;throw error;});
 return templatePromise;
}

export function downloadCouponPdf(bytes,filename,documentRef=document) {
 const blob=new Blob([bytes],{type:'application/pdf'}),url=URL.createObjectURL(blob),link=documentRef.createElement('a');link.href=url;link.download=filename;documentRef.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
}
