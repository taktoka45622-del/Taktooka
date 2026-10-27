import {$,invoke,run,notice,problem,eye} from './client.js';
let token=location.hash.slice(1);history.replaceState(null,'',location.pathname);eye($('password'),$('eye'));
if(!/^[a-f0-9]{64}$/.test(token)){notice('افتح الرابط الكامل المرسل إلك من الإدارة.',true);$('resetForm').hidden=true;}
$('resetForm').onsubmit=e=>{e.preventDefault();run(async()=>{if($('password').value!==$('confirm').value)problem('كلمتا السر مو متطابقتين.');await invoke('taktooka-password-link',{op:'redeem',token,password:$('password').value});token='';$('password').value='';$('confirm').value='';$('resetForm').hidden=true;notice('تم تغيير كلمة السر بنجاح. تكدر هسه تدخل بالموقع والتطبيق بالكلمة الجديدة.');});};
