export function normalizeIraqiPhone(value){
 const digits=String(value??'').normalize('NFKC').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776));
 const cleaned=digits.replace(/[\s\u061c\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff()\-\u2010-\u2015]/g,'');
 if(/^07[0-9]{9}$/.test(cleaned))return '+964'+cleaned.slice(1);
 if(/^7[0-9]{9}$/.test(cleaned))return '+964'+cleaned;
 if(/^\+9647[0-9]{9}$/.test(cleaned))return cleaned;
 if(/^9647[0-9]{9}$/.test(cleaned))return '+'+cleaned;
 if(/^009647[0-9]{9}$/.test(cleaned))return '+'+cleaned.slice(2);
 return null;
}
