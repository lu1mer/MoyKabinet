'use strict';
const $ = id => document.getElementById(id);
const cabinet = new URLSearchParams(location.search).get('cabinet');
let services = [], service = null, selected = null, booked = null, slotVersion = 0, requestID = null;
const money = n => new Intl.NumberFormat('ru-RU', {style:'currency',currency:'RUB',maximumFractionDigits:0}).format(n);
function error(message) { $('error').textContent = message; $('error').hidden = !message; }
async function api(path, options = {}) {
  const response = await fetch(`/api/public/${cabinet}${path}`, options);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Не удалось связаться с кабинетом.');
  return data;
}
function update() {
  $('submit').disabled = !service || selected === null;
  $('summary').textContent = service ? `${service.name} · ${money(service.price)}${selected === null ? '' : ' · ' + new Date((selected + 978307200)*1000).toLocaleString('ru-RU',{timeZone:booked?.timezone || $('zone').dataset.zone,day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})}` : 'Выберите услугу и время';
}
async function loadSlots() {
  const version = ++slotVersion; selected = null; requestID = null; update(); $('slots').replaceChildren();
  if (!service || !$('date').value) return;
  $('slots').textContent = 'Ищем свободное время…';
  try {
    const result = await api(`/slots?service=${encodeURIComponent(service.id)}&date=${encodeURIComponent($('date').value)}`);
    if (version !== slotVersion) return;
    $('slots').replaceChildren();
    if (!result.slots.length) $('slots').textContent = 'На этот день свободных окон нет. Попробуйте другую дату.';
    for (const slot of result.slots) {
      const button = document.createElement('button'); button.type = 'button'; button.className = 'slot'; button.textContent = slot.label; button.setAttribute('aria-pressed','false');
      button.onclick = () => { selected = slot.start; requestID = null; document.querySelectorAll('.slot').forEach(b => b.setAttribute('aria-pressed',String(b === button))); update(); };
      $('slots').append(button);
    }
  } catch (e) { if (version === slotVersion) { $('slots').textContent = 'Не удалось загрузить время. Выберите дату ещё раз.'; error(e.message); } }
}
async function init() {
  if (!cabinet || !/^[a-f0-9]{32}$/.test(cabinet)) { $('loading').hidden = true; $('subtitle').textContent = 'Откройте персональную ссылку, которую прислал ваш мастер.'; return; }
  try {
    const data = await api(''); services = data.services;
    $('title').textContent = data.profile.name; $('specialty').textContent = data.profile.specialty || 'ЗАПИСЬ К МАСТЕРУ';
    $('zone').textContent = `Время кабинета: ${data.profile.timezone.replaceAll('_',' ')}`; $('zone').dataset.zone = data.profile.timezone;
    const date = new Intl.DateTimeFormat('en-CA', {timeZone:data.profile.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
    $('date').min = date; $('date').value = date;
    const max = new Date(Date.now()+60*86400000); $('date').max = new Intl.DateTimeFormat('en-CA',{timeZone:data.profile.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(max);
    for (const item of services) {
      const b = document.createElement('button'); b.type='button'; b.className='service'; b.setAttribute('aria-pressed','false');
      const circle = document.createElement('span'); circle.className='circle';
      const details = document.createElement('span'); details.className='details'; details.textContent = item.name;
      const duration = document.createElement('small'); duration.textContent = `${item.minutes} минут`; details.append(duration);
      const price = document.createElement('span'); price.className='price'; price.textContent = money(item.price); b.append(circle,details,price);
      b.onclick = () => { service=item; error(''); document.querySelectorAll('.service').forEach(s=>s.setAttribute('aria-pressed',String(s===b))); loadSlots(); };
      $('services').append(b);
    }
    $('booking').hidden=false;
    if (!services.length) { $('booking').hidden=true; error('Мастер пока не добавил услуги. Загляните позже.'); }
    else $('services').firstElementChild.click();
  } catch (e) { error(e.message); } finally { $('loading').hidden=true; }
}
$('date').onchange = () => { error(''); loadSlots(); };
for (const id of ['name', 'phone', 'consent']) {
  $(id).addEventListener('input', () => { requestID = null; });
  $(id).addEventListener('change', () => { requestID = null; });
}
$('booking').onsubmit = async event => {
  event.preventDefault(); if (!service || selected === null) return;
  const phone=$('phone').value.trim(); if (!/^[+\d() \-]{7,30}$/.test(phone) || phone.replace(/\D/g,'').length < 7) { error('Проверьте номер телефона.'); return; }
  $('submit').disabled=true; $('submit').textContent='Сохраняем…'; error('');
  // Retain the same idempotency key after a network failure so retry cannot duplicate a booking.
  requestID ||= crypto.randomUUID();
  try {
    booked = await api('/book',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({serviceID:service.id,start:selected,name:$('name').value.trim(),phone,consent:$('consent').checked,requestID})});
    $('booking').hidden=true; $('success').hidden=false;
    $('confirmation').textContent = `${booked.serviceName} · ${new Date((booked.start+978307200)*1000).toLocaleString('ru-RU',{timeZone:booked.timezone,day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})} · ${money(booked.price)}`;
    $('success').scrollIntoView({behavior:'smooth'});
  } catch(e) { error(e.message); $('error').scrollIntoView({behavior:'smooth'}); }
  finally { $('submit').textContent='Записаться ↗'; update(); }
};
$('calendar').onclick=()=>{
  if(!booked)return;
  const stamp=n=>new Date(n*1000).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}/,'');
  const escape=s=>s.replaceAll('\\','\\\\').replaceAll('\n','\\n').replaceAll(',','\\,').replaceAll(';','\\;').replaceAll('\r','');
  const text=`BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//MoyKabinet//Booking//RU\r\nBEGIN:VEVENT\r\nUID:${booked.id}@moykabinet\r\nDTSTAMP:${stamp(Date.now()/1000)}\r\nDTSTART:${stamp(booked.start+978307200)}\r\nDTEND:${stamp(booked.start+978307200+booked.minutes*60)}\r\nSUMMARY:${escape(booked.serviceName)}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`;
  const url=URL.createObjectURL(new Blob([text],{type:'text/calendar;charset=utf-8'})); const a=document.createElement('a');a.href=url;a.download='Встреча.ics';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
};
init();
