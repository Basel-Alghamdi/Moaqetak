// مؤقتك - تطبيق ويب بسيط (واجهة عربية + نظام مظلم)

// حدود تقريبية للمملكة (لإنشاء إحداثيات وهمية معقولة)
const KSA_BOUNDS = {
  latMin: 16.0,
  latMax: 32.0,
  lngMin: 34.0,
  lngMax: 56.0,
};

const TZ_RIYADH = 'Asia/Riyadh';
const LOCALE_AR_SA = 'ar-SA';

// عناصر DOM
const splashOverlay = document.getElementById('splashOverlay');
const emptyState = document.getElementById('emptyState');
const resultCard = document.getElementById('resultCard');
const leaveTimeText = document.getElementById('leaveTimeText');
const destLabel = document.getElementById('destLabel');
const arrivalLabel = document.getElementById('arrivalLabel');
const travelLabel = document.getElementById('travelLabel');

const appointmentModal = document.getElementById('appointmentModal');
const closeModalBtn = document.getElementById('closeModalBtn');
const newAppointmentBtn = document.getElementById('newAppointmentBtn');
const createFromEmptyBtn = document.getElementById('createFromEmptyBtn');
const form = document.getElementById('appointmentForm');
const formErrors = document.getElementById('formErrors');

const originLatInput = document.getElementById('originLat');
const originLngInput = document.getElementById('originLng');
const destLatInput = document.getElementById('destLat');
const destLngInput = document.getElementById('destLng');
const originCoordsText = document.getElementById('originCoordsText');
const destCoordsText = document.getElementById('destCoordsText');

const dateInput = document.getElementById('dateInput');
const timeInput = document.getElementById('timeInput');
const prepMinutesInput = document.getElementById('prepMinutes');
const delayMinutesInput = document.getElementById('delayMinutes');

// خريطة تجريبية
const mapPicker = document.getElementById('mapPicker');
const mapCanvas = document.getElementById('mapCanvas');
const closeMapBtn = document.getElementById('closeMapBtn');
const confirmPickBtn = document.getElementById('confirmPickBtn');
const pickedCoords = document.getElementById('pickedCoords');

let mapMarkerEl = null;
let mapPickTarget = null; // 'origin' | 'dest'
let pickedLatLng = null;

// أدوات الوقت (صياغة الوقت بتوقيت مكة بصيغة 12 ساعة)
function formatTimeRiyadh(date) {
  return new Intl.DateTimeFormat(LOCALE_AR_SA, {
    hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ_RIYADH,
  }).format(date);
}

function formatDateTimeRiyadh(date) {
  return new Intl.DateTimeFormat(LOCALE_AR_SA, {
    weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ_RIYADH,
  }).format(date);
}

// نحصل على "الآن" بتوقيت الرياض كأجزاء
function nowInRiyadhParts() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ_RIYADH,
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    hour12: false,
  }).formatToParts(Date.now()).reduce((acc, p) => (acc[p.type] = p.value, acc), {});
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
  };
}

// نحول تاريخ/وقت (بتوقيت مكة) إلى كائن Date عبر UTC ثابت (UTC+3)
function riyadhLocalToDate(year, month, day, hour, minute) {
  // آسيا/الرياض ثابتة على UTC+3
  const d = new Date(Date.UTC(year, month - 1, day, hour - 3, minute, 0));
  return d;
}

// Haversine لحساب المسافة بالكيلومترات
function haversineKm(lat1, lon1, lat2, lon2) {
  const toRad = (d) => d * Math.PI / 180;
  const R = 6371; // km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon/2)**2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// مدة الرحلة التقديرية (بيانات وهمية): 1.5 دقيقة لكل كم + 5 دقائق (بحث موقف/إشارات)
function estimateTravelMinutes(origin, dest) {
  const km = haversineKm(origin.lat, origin.lng, dest.lat, dest.lng);
  return Math.round(km * 1.5 + 5);
}

// إدارة الواجهة
function openModal() { appointmentModal.classList.remove('hidden'); }
function closeModal() { appointmentModal.classList.add('hidden'); formErrors.textContent = ''; }
function openMap() { mapPicker.classList.remove('hidden'); }
function closeMap() { mapPicker.classList.add('hidden'); resetMapSelection(); }

function resetMapSelection() {
  pickedLatLng = null;
  pickedCoords.textContent = '—';
  confirmPickBtn.disabled = true;
  if (mapMarkerEl) { mapMarkerEl.remove(); mapMarkerEl = null; }
}

function setDefaultDateTime() {
  const now = nowInRiyadhParts();
  const pad = (n) => String(n).padStart(2, '0');
  dateInput.value = `${now.year}-${pad(now.month)}-${pad(now.day)}`;
  timeInput.value = `${pad(now.hour)}:${pad(now.minute)}`;
}

function renderResultCard(state) {
  if (!state) {
    resultCard.classList.add('hidden');
    emptyState.classList.remove('hidden');
    return;
  }

  emptyState.classList.add('hidden');
  resultCard.classList.remove('hidden');

  leaveTimeText.textContent = formatTimeRiyadh(new Date(state.leaveAt));
  arrivalLabel.textContent = formatDateTimeRiyadh(new Date(state.arriveAt));
  travelLabel.textContent = `${state.travelMinutes} دقيقة`;
  destLabel.textContent = state.destLabel || `(${state.destination.lat.toFixed(4)}, ${state.destination.lng.toFixed(4)})`;
}

function saveAppointment(state) {
  localStorage.setItem('mowaqetak_last', JSON.stringify(state));
}
function loadAppointment() {
  const raw = localStorage.getItem('mowaqetak_last');
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

// تهيئة
document.addEventListener('DOMContentLoaded', () => {
  // إخفاء شاشة البداية بعد لحظة بسيطة
  setTimeout(() => splashOverlay.classList.add('hidden'), 600);

  // تعبئة التاريخ والوقت الافتراضي
  setDefaultDateTime();

  // تحميل نتيجة محفوظة
  renderResultCard(loadAppointment());

  // أزرار فتح/إغلاق النوافذ
  newAppointmentBtn.addEventListener('click', () => { openModal(); });
  createFromEmptyBtn.addEventListener('click', () => { openModal(); });
  closeModalBtn.addEventListener('click', closeModal);

  // اختيار من الخريطة (أصل/وجهة)
  document.getElementById('pickOriginBtn').addEventListener('click', () => {
    mapPickTarget = 'origin';
    openMap();
  });

  document.getElementById('pickDestinationBtn').addEventListener('click', () => {
    mapPickTarget = 'dest';
    openMap();
  });

  closeMapBtn.addEventListener('click', closeMap);

  // تعامل مع النقر على الخريطة التجريبية
  mapCanvas.addEventListener('click', (e) => {
    const rect = mapCanvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const pxX = x / rect.width;  // 0..1
    const pxY = y / rect.height; // 0..1

    const lat = KSA_BOUNDS.latMax - (KSA_BOUNDS.latMax - KSA_BOUNDS.latMin) * pxY;
    const lng = KSA_BOUNDS.lngMin + (KSA_BOUNDS.lngMax - KSA_BOUNDS.lngMin) * pxX;

    pickedLatLng = { lat, lng };
    pickedCoords.textContent = `خط العرض ${lat.toFixed(4)}، خط الطول ${lng.toFixed(4)}`;
    confirmPickBtn.disabled = false;

    if (!mapMarkerEl) {
      mapMarkerEl = document.createElement('div');
      mapMarkerEl.className = 'map-marker';
      mapCanvas.appendChild(mapMarkerEl);
    }
    mapMarkerEl.style.left = `${x}px`;
    mapMarkerEl.style.top = `${y}px`;
  });

  confirmPickBtn.addEventListener('click', () => {
    if (!pickedLatLng || !mapPickTarget) return;
    if (mapPickTarget === 'origin') {
      originLatInput.value = String(pickedLatLng.lat);
      originLngInput.value = String(pickedLatLng.lng);
      originCoordsText.textContent = `${pickedLatLng.lat.toFixed(4)}, ${pickedLatLng.lng.toFixed(4)}`;
    } else {
      destLatInput.value = String(pickedLatLng.lat);
      destLngInput.value = String(pickedLatLng.lng);
      destCoordsText.textContent = `${pickedLatLng.lat.toFixed(4)}, ${pickedLatLng.lng.toFixed(4)}`;
    }
    closeMap();
  });

  // حفظ الموعد
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    formErrors.textContent = '';

    const origin = getPointFromInputs(originLatInput, originLngInput);
    const destination = getPointFromInputs(destLatInput, destLngInput);
    if (!origin || !destination) {
      formErrors.textContent = 'يرجى تحديد الموقع والوجهة من الخريطة.';
      return;
    }

    if (!dateInput.value || !timeInput.value) {
      formErrors.textContent = 'يرجى إدخال تاريخ ووقت الموعد.';
      return;
    }

    const [y, m, d] = dateInput.value.split('-').map(Number);
    const [hh, mm] = timeInput.value.split(':').map(Number);
    const arriveAt = riyadhLocalToDate(y, m, d, hh, mm).getTime();

    const prepMin = clampNonNegInt(prepMinutesInput.value, 0);
    const delayMin = clampNonNegInt(delayMinutesInput.value, 0);
    const travelMin = estimateTravelMinutes(origin, destination);

    const totalBefore = (prepMin + delayMin + travelMin) * 60_000;
    const leaveAt = arriveAt - totalBefore;

    const state = {
      origin,
      destination,
      destLabel: 'الوجهة المحددة',
      arriveAt,
      leaveAt,
      travelMinutes: travelMin,
      prepMinutes: prepMin,
      delayMinutes: delayMin,
    };

    saveAppointment(state);
    renderResultCard(state);
    closeModal();
  });
});

function clampNonNegInt(value, fallback) {
  const n = Math.max(0, Math.floor(Number(value)));
  return Number.isFinite(n) ? n : fallback;
}

function getPointFromInputs(latEl, lngEl) {
  const lat = Number(latEl.value);
  const lng = Number(lngEl.value);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

