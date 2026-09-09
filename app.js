const seedDrawers = [
  { id: 1, name: 'Đồ điện tử', area: 'Phòng khách', color: 'coral', description: 'Cáp sạc, pin dự phòng và tai nghe.', items: 12, updated: 'Hôm nay', organized: true },
  { id: 2, name: 'Văn phòng phẩm', area: 'Phòng làm việc', color: 'blue', description: 'Bút, giấy ghi chú và đồ dùng nhỏ.', items: 24, updated: 'Hôm qua', organized: true },
  { id: 3, name: 'Chìa khóa & khóa', area: 'Lối vào', color: 'yellow', description: 'Chìa khóa dự phòng và ổ khóa.', items: 8, updated: '2 ngày trước', organized: false },
  { id: 4, name: 'Đồ may vá', area: 'Phòng ngủ', color: 'green', description: 'Kim chỉ, cúc áo và kéo nhỏ.', items: 16, updated: '5 ngày trước', organized: true },
  { id: 5, name: 'Thuốc gia đình', area: 'Phòng tắm', color: 'blue', description: 'Thuốc thông dụng và băng cá nhân.', items: 9, updated: 'Tuần trước', organized: false }
];
const defaultAreas = ['Phòng khách', 'Phòng làm việc', 'Lối vào', 'Phòng ngủ', 'Phòng tắm'];
let drawers = JSON.parse(localStorage.getItem('ngan-keo-drawers')) || seedDrawers;
let areas = JSON.parse(localStorage.getItem('ngan-keo-areas')) || defaultAreas;
let currentView = 'all';
let currentArea = '';

const $ = (selector) => document.querySelector(selector);
const drawerGrid = $('#drawer-grid');
const save = () => { localStorage.setItem('ngan-keo-drawers', JSON.stringify(drawers)); localStorage.setItem('ngan-keo-areas', JSON.stringify(areas)); };
const iconFor = (color) => ({ coral: '⌁', blue: '✦', green: '⌘', yellow: '⊙' })[color] || '▦';

function renderAreas() {
  $('#area-list').innerHTML = `<div class="area-item ${!currentArea ? 'selected' : ''}" data-area="">Tất cả khu vực <small>${drawers.length}</small></div>` + areas.map((area) => `<div class="area-item ${currentArea === area ? 'selected' : ''}" data-area="${area}">${area} <small>${drawers.filter((drawer) => drawer.area === area).length}</small></div>`).join('');
  $('#area-select').innerHTML = areas.map((area) => `<option value="${area}">${area}</option>`).join('');
  document.querySelectorAll('.area-item').forEach((item) => item.addEventListener('click', () => { currentArea = item.dataset.area; currentView = 'all'; document.querySelectorAll('.nav-item').forEach((nav) => nav.classList.toggle('active', nav.dataset.view === 'all')); render(); }));
}

function filteredDrawers() {
  const search = $('#search-input').value.trim().toLowerCase();
  return drawers.filter((drawer) => {
    const matchesSearch = !search || `${drawer.name} ${drawer.area} ${drawer.description}`.toLowerCase().includes(search);
    const matchesArea = !currentArea || drawer.area === currentArea;
    const matchesView = currentView === 'all' || (currentView === 'attention' && !drawer.organized) || (currentView === 'recent' && ['Hôm nay', 'Hôm qua', '2 ngày trước'].includes(drawer.updated));
    return matchesSearch && matchesArea && matchesView;
  });
}

function render() {
  renderAreas();
  const visible = filteredDrawers();
  drawerGrid.innerHTML = visible.length ? visible.map((drawer) => `<article class="drawer-card"><div class="drawer-top"><div class="drawer-color ${drawer.color}">${iconFor(drawer.color)}</div><button class="more-button" data-delete="${drawer.id}" aria-label="Xóa ${drawer.name}">•••</button></div><h3>${drawer.name}</h3><p>${drawer.description || 'Chưa có mô tả.'}</p><div class="drawer-meta"><span>${drawer.items} vật dụng</span><span class="status ${drawer.organized ? 'ready' : ''}">${drawer.organized ? 'Đã sắp xếp' : 'Cần sắp xếp'}</span></div></article>`).join('') : '<div class="empty-state"><strong>Chưa tìm thấy ngăn kéo</strong>Thử đổi từ khóa hoặc tạo một ngăn kéo mới.</div>';
  $('#drawer-count').textContent = drawers.length;
  $('#organized-count').textContent = drawers.filter((drawer) => drawer.organized).length;
  $('#item-count').textContent = drawers.reduce((total, drawer) => total + drawer.items, 0);
  const percent = Math.min(100, Math.round(drawers.length / 12 * 100));
  $('#storage-percent').textContent = `${percent}%`; $('#storage-progress').style.width = `${percent}%`; $('#storage-summary').textContent = `${drawers.length} / 12 ngăn kéo`;
  document.querySelectorAll('[data-delete]').forEach((button) => button.addEventListener('click', () => { drawers = drawers.filter((drawer) => drawer.id !== Number(button.dataset.delete)); save(); render(); showToast('Đã xóa ngăn kéo'); }));
}

function openModal() { $('#modal-backdrop').hidden = false; $('#drawer-form input').focus(); }
function closeModal() { $('#modal-backdrop').hidden = true; $('#drawer-form').reset(); }
function showToast(message) { const toast = $('#toast'); toast.textContent = message; toast.classList.add('show'); setTimeout(() => toast.classList.remove('show'), 2400); }

document.querySelectorAll('.nav-item').forEach((button) => button.addEventListener('click', () => { currentView = button.dataset.view; currentArea = ''; document.querySelectorAll('.nav-item').forEach((nav) => nav.classList.toggle('active', nav === button)); const titles = { all: ['Tất cả ngăn kéo', 'Một góc nhìn rõ ràng về mọi thứ bạn đang cất giữ.'], recent: ['Cập nhật gần đây', 'Những ngăn kéo bạn vừa ghé qua.'], attention: ['Cần sắp xếp', 'Một chút chú ý để mọi thứ trở nên dễ tìm hơn.'] }; $('#view-title').textContent = titles[currentView][0]; $('#view-description').textContent = titles[currentView][1]; render(); }));
$('#search-input').addEventListener('input', render); $('#add-drawer').addEventListener('click', openModal); $('#modal-close').addEventListener('click', closeModal); $('#modal-backdrop').addEventListener('click', (event) => { if (event.target === $('#modal-backdrop')) closeModal(); });
$('#drawer-form').addEventListener('submit', (event) => { event.preventDefault(); const form = new FormData(event.target); drawers.unshift({ id: Date.now(), name: form.get('name'), area: form.get('area'), color: form.get('color'), description: form.get('description'), items: 0, updated: 'Vừa xong', organized: false }); save(); render(); closeModal(); showToast('Ngăn kéo mới đã được tạo'); });
$('#add-area').addEventListener('click', () => { const area = window.prompt('Tên khu vực mới:'); if (area && !areas.includes(area.trim())) { areas.push(area.trim()); save(); render(); showToast('Đã thêm khu vực'); } });
document.addEventListener('keydown', (event) => { if (event.key === '/' && document.activeElement.tagName !== 'INPUT') { event.preventDefault(); $('#search-input').focus(); } if (event.key === 'Escape') closeModal(); });
$('#theme-toggle').addEventListener('click', () => { document.body.classList.toggle('warm-mode'); showToast('Đã đổi sắc thái giao diện'); });
render();