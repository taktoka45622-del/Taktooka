self.addEventListener('notificationclick',event=>{event.notification.close();event.stopImmediatePropagation();event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{const url=new URL('./',self.registration.scope).href;const tab=list.find(c=>c.url.startsWith(self.registration.scope));return tab?tab.focus():clients.openWindow(url);}));});
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging-compat.js');
fetch('../firebase-config.json').then(r=>r.json()).then(config=>{firebase.initializeApp(config);firebase.messaging();});
