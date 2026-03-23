import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
import {
    getFirestore, collection, addDoc, onSnapshot, serverTimestamp,
    query, orderBy, updateDoc, doc, deleteDoc, setDoc, getDocs,
    getDoc, where, limit, Timestamp
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-firestore.js";

const firebaseConfig = {
    apiKey:            "AIzaSyBfnO29PNacfCnUMSHBPyOze-H5wt80D-g",
    authDomain:        "card-scanner-1338a.firebaseapp.com",
    projectId:         "card-scanner-1338a",
    storageBucket:     "card-scanner-1338a.firebasestorage.app",
    messagingSenderId: "300868355176",
    appId:             "1:300868355176:web:9e6eb811ddae19dd39e7dd"
};

const app = initializeApp(firebaseConfig);
const db  = getFirestore(app);

let allLicenses   = [];
let allUsers      = [];
let currentFilter = 'all';
let currentSearch = '';
let userSearch    = '';

// ── DOM refs ──────────────────────────────────────────────────────────────────
const tableBody    = document.getElementById('tableBody');
const usersTableBody = document.getElementById('usersTableBody');
const activityFeed = document.getElementById('activityFeed');
const totalCount   = document.getElementById('totalCount');
const activeCount  = document.getElementById('activeCount');
const pendingCount = document.getElementById('pendingCount');
const blockedCount = document.getElementById('blockedCount');
const expiredCount = document.getElementById('expiredCount');
const deletedCount = document.getElementById('deletedCount');

// ── License actions ───────────────────────────────────────────────────────────

window.toggleBlock = async (id, status) => {
    const lic = allLicenses.find(l => l.id === id);
    if (!lic) return alert("License not found.");
    if (lic.status === 'deleted' || lic.status === 'expired') {
        return alert("Deleted or Expired licenses cannot be modified.");
    }
    try {
        let newStatus;
        if (status === 'blocked') {
            newStatus = lic.deviceId ? 'active' : 'pending';
            await logActivity(lic.key, "Unblocked", lic.deviceModel || "System");
        } else {
            newStatus = 'blocked';
            await logActivity(lic.key, "Blocked", lic.deviceModel || "System");
        }
        await updateDoc(doc(db, "licenses", id), { status: newStatus });
    } catch (e) { alert("Failed: " + e.message); }
};

window.resetDevice = async (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (!lic) return alert("License not found.");
    if (lic.status === 'deleted' || lic.status === 'expired') {
        return alert("Deleted or Expired licenses cannot be reset.");
    }
    if (!confirm(`Reset device for ${lic.key}? The user must re-activate.`)) return;
    try {
        await logActivity(lic.key, "Reset device link", lic.deviceModel || "System");
        await updateDoc(doc(db, "licenses", id), {
            deviceId: "", deviceModel: "", deviceOS: "", status: "pending"
        });
    } catch (e) { alert("Failed: " + e.message); }
};

window.markDeleted = async (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (!lic || lic.status === 'deleted') return;
    if (!confirm(`Permanently delete ${lic.key}? This cannot be undone.`)) return;
    try {
        await logActivity(lic.key, "Deleted license");
        await updateDoc(doc(db, "licenses", id), {
            status: 'deleted', deviceId: "", deviceModel: "", deviceOS: ""
        });
    } catch (e) { alert("Failed: " + e.message); }
};

window.extendKey = (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (!lic || lic.status === 'deleted') return alert("Cannot extend a deleted license.");

    document.getElementById('extendModal').style.display = 'flex';

    const update = () => {
        const days = parseInt(document.getElementById('extendDays').value) || 0;
        const base = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
        const newExpiry = new Date(base.getTime() + days * 86400000);
        document.getElementById('extendCurrentExpiry').textContent =
            `Current expiry: ${lic.expiryDate ? base.toLocaleDateString() : 'Not yet activated'}`;
        document.getElementById('extendNewExpiry').textContent =
            `New expiry after extension: ${newExpiry.toLocaleDateString()}`;
    };
    document.getElementById('extendDays').oninput = update;
    update();

    document.getElementById('confirmExtendBtn').onclick = async () => {
        const days = parseInt(document.getElementById('extendDays').value);
        if (!days || days < 1) return alert("Enter a valid number of days.");
        const base = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
        const newExpiry = new Date(base.getTime() + days * 86400000);
        let newStatus = lic.status === 'expired' ? (lic.deviceId ? 'active' : 'pending') : lic.status;
        try {
            await updateDoc(doc(db, "licenses", id), {
                expiryDate: Timestamp.fromDate(newExpiry), status: newStatus
            });
            await logActivity(lic.key, `Extended by ${days} day${days===1?'':'s'}`, lic.deviceModel || "System");
            document.getElementById('extendModal').style.display = 'none';
            alert(`✅ Extended to ${newExpiry.toLocaleDateString()}`);
        } catch (e) { alert("Failed: " + e.message); }
    };
};

window.hideExtendModal = () => document.getElementById('extendModal').style.display = 'none';

window.openUserNoteModal = (deviceId, note) => {
    document.getElementById('noteModal').style.display = 'flex';
    document.getElementById('userNoteText').value = note;
    document.getElementById('saveNoteBtn').onclick = async () => {
        try {
            await updateDoc(doc(db, "users", deviceId), {
                adminNotes: document.getElementById('userNoteText').value
            });
            document.getElementById('noteModal').style.display = 'none';
        } catch (e) { alert("Failed: " + e.message); }
    };
};

window.showModal  = () => document.getElementById('genModal').style.display = 'flex';
window.hideModal  = () => document.getElementById('genModal').style.display = 'none';

window.handleGenerate = async () => {
    const prefix      = document.getElementById('prefix').value.toUpperCase() || 'RAK';
    const durationVal = document.getElementById('duration').value;
    const qty         = parseInt(document.getElementById('qty').value);
    if (qty < 1 || qty > 100) return;

    const btn = document.getElementById('genBtn');
    btn.disabled   = true;
    btn.innerText  = "Generating...";

    for (let i = 0; i < qty; i++) {
        const random   = Math.random().toString(36).substring(2, 10).toUpperCase();
        const checksum = [...(prefix + random)].reduce((a, b) => a + b.charCodeAt(0), 0) % 10;
        const key      = `${prefix}-${random}-${checksum}`;
        const docData  = { key, deviceId: "", status: "pending", createdAt: serverTimestamp(), activatedAt: null, expiryDate: null };

        if      (durationVal === "3")   docData.durationDays   = 3;
        else if (durationVal === "120") docData.lifetime       = true;
        else                            docData.durationMonths = parseInt(durationVal);

        await addDoc(collection(db, "licenses"), docData);
        await logActivity(key, "Generated license");
    }

    btn.disabled  = false;
    btn.innerText = "Generate & Save";
    document.getElementById('genModal').style.display = 'none';
};

// ── Auth ──────────────────────────────────────────────────────────────────────

if (localStorage.getItem('admin_session') === 'true') showDashboard();

document.getElementById('loginBtn').onclick = async () => {
    const entered = document.getElementById('adminPass').value;
    const btn = document.getElementById('loginBtn');
    btn.disabled  = true;
    btn.innerText = "Verifying...";
    try {
        const snap = await getDoc(doc(db, "settings", "global"));
        if (!snap.exists()) return alert("Dashboard not configured. Add adminPassword to settings/global.");
        const correct = snap.data().adminPassword;
        if (!correct) return alert("No admin password set. Add adminPassword field to settings/global.");
        if (entered === correct) {
            localStorage.setItem('admin_session', 'true');
            showDashboard();
        } else {
            document.getElementById('loginError').style.display = 'block';
        }
    } catch (e) {
        alert("Verification failed. Check internet.\n" + e.message);
    } finally {
        btn.disabled  = false;
        btn.innerText = "Unlock Dashboard";
    }
};

function showDashboard() {
    document.getElementById('loginScreen').style.display   = 'none';
    document.getElementById('dashboardContent').style.display = 'flex';
    startListeners();
    bindSettingsButtons();
}

// ── Tab switching ─────────────────────────────────────────────────────────────

document.querySelectorAll('#mainNav a[data-tab]').forEach(link => {
    link.onclick = e => {
        e.preventDefault();
        const tab = link.getAttribute('data-tab');
        document.querySelectorAll('.tab-page').forEach(p => p.classList.remove('active'));
        document.querySelectorAll('#mainNav a').forEach(l => l.classList.remove('active'));
        document.getElementById(`tab-${tab}`).classList.add('active');
        link.classList.add('active');
    };
});

document.querySelectorAll('.stat-card.clickable').forEach(card => {
    card.onclick = () => {
        document.querySelectorAll('.stat-card.clickable').forEach(c => c.classList.remove('active'));
        card.classList.add('active');
        currentFilter = card.getAttribute('data-filter');
        renderLicenses();
    };
});

// ── Activity logging + auto-trim ──────────────────────────────────────────────

async function logActivity(key, action, device = "System") {
    try {
        await addDoc(collection(db, "activity"), { key, action, device, timestamp: serverTimestamp() });
        trimActivityLogs();
    } catch(e) { console.error("Log error:", e); }
}

async function trimActivityLogs() {
    try {
        const all = await getDocs(query(collection(db, "activity"), orderBy("timestamp", "asc")));
        if (all.size > 100) {
            for (const d of all.docs.slice(0, all.size - 100)) await deleteDoc(d.ref);
        }
    } catch(e) { console.error("Trim error:", e); }
}

// ── Settings buttons ──────────────────────────────────────────────────────────

function bindSettingsButtons() {
    // Announcement
    document.getElementById('saveAnnouncementBtn').onclick = async () => {
        const text = document.getElementById('setting-announcement').value.trim();
        try {
            await setDoc(doc(db, "settings", "global"), {
                announcement: text, announcementId: `ann_${Date.now()}`
            }, { merge: true });
            alert("Announcement saved — it will appear in all active apps.");
        } catch (e) { alert("Failed: " + e.message); }
    };

    // Support link
    document.getElementById('saveSupportBtn').onclick = async () => {
        const link = document.getElementById('setting-support').value.trim();
        try {
            await setDoc(doc(db, "settings", "global"), { supportLink: link }, { merge: true });
            alert("Support link updated!");
        } catch (e) { alert("Failed: " + e.message); }
    };

    // Kill switch
    document.getElementById('setting-killswitch').onchange = async e => {
        const isOn = e.target.checked;
        if (!confirm(isOn ? "⚠️ Enable Kill-Switch? ALL users will be blocked immediately." : "Re-enable app for all users?")) {
            e.target.checked = !isOn; return;
        }
        try {
            await setDoc(doc(db, "settings", "global"), { killSwitch: isOn }, { merge: true });
        } catch (e) { alert("Failed: " + e.message); e.target.checked = !isOn; }
    };

    // Change password
    document.getElementById('savePasswordBtn').onclick = async () => {
        const np = document.getElementById('setting-password').value.trim();
        const nc = document.getElementById('setting-password-confirm').value.trim();
        if (!np || np.length < 6) return alert("Password must be at least 6 characters.");
        if (np !== nc) return alert("Passwords do not match.");
        if (!confirm("Change admin password?")) return;
        try {
            await setDoc(doc(db, "settings", "global"), { adminPassword: np }, { merge: true });
            document.getElementById('setting-password').value         = '';
            document.getElementById('setting-password-confirm').value = '';
            alert("✅ Password changed!");
        } catch (e) { alert("Failed: " + e.message); }
    };

    // ── Update management ─────────────────────────────────────────────────────
    document.getElementById('saveUpdateBtn').onclick = async () => {
        const latest      = document.getElementById('setting-latest-version').value.trim();
        const minVer      = document.getElementById('setting-min-version').value.trim();
        const apkUrl      = document.getElementById('setting-apk-url').value.trim();
        const updateNotes = document.getElementById('setting-update-notes').value.trim();

        if (!latest) return alert("Latest version is required (e.g. 1.0.1)");
        const versionPattern = /^\d+\.\d+\.\d+$/;
        if (!versionPattern.test(latest)) return alert("Version format must be X.Y.Z (e.g. 1.2.0)");
        if (minVer && !versionPattern.test(minVer)) return alert("Min version format must be X.Y.Z");

        try {
            await setDoc(doc(db, "settings", "global"), {
                latestVersion: latest,
                minVersion:    minVer  || latest,
                apkUrl:        apkUrl,
                updateNotes:   updateNotes
            }, { merge: true });
            alert(`✅ Update info saved!\nLatest: ${latest}\nMin allowed: ${minVer || latest}\n\nUsers on older versions will see the update prompt.`);
        } catch (e) { alert("Failed: " + e.message); }
    };
}

// ── Listeners ─────────────────────────────────────────────────────────────────

function startListeners() {
    onSnapshot(query(collection(db, "licenses"), orderBy("createdAt", "desc")), snap => {
        allLicenses = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        updateStats();
        renderLicenses();
    });

    onSnapshot(query(collection(db, "users"), orderBy("lastActive", "desc")), snap => {
        allUsers = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        renderUsers();
    });

    onSnapshot(query(collection(db, "activity"), orderBy("timestamp", "desc"), limit(100)), snap => {
        renderActivity(snap.docs.map(d => d.data()));
    });

    onSnapshot(doc(db, "settings", "global"), snap => {
        if (!snap.exists()) return;
        const data = snap.data();
        if (document.activeElement !== document.getElementById('setting-announcement'))
            document.getElementById('setting-announcement').value = data.announcement || '';
        document.getElementById('setting-support').value          = data.supportLink   || '';
        document.getElementById('setting-killswitch').checked     = data.killSwitch    || false;
        document.getElementById('killSwitchStatus').innerText     = data.killSwitch ? "APP IS DISABLED (KILL-SWITCH ON)" : "App is Live";
        document.getElementById('killSwitchStatus').style.color   = data.killSwitch ? "red" : "green";

        // Populate update fields (don't overwrite if user is typing)
        if (document.activeElement !== document.getElementById('setting-latest-version'))
            document.getElementById('setting-latest-version').value = data.latestVersion || '';
        if (document.activeElement !== document.getElementById('setting-min-version'))
            document.getElementById('setting-min-version').value    = data.minVersion    || '';
        if (document.activeElement !== document.getElementById('setting-apk-url'))
            document.getElementById('setting-apk-url').value        = data.apkUrl        || '';
        if (document.activeElement !== document.getElementById('setting-update-notes'))
            document.getElementById('setting-update-notes').value   = data.updateNotes   || '';
    });
}

// ── Render ────────────────────────────────────────────────────────────────────

function updateStats() {
    totalCount.innerText   = allLicenses.length;
    activeCount.innerText  = allLicenses.filter(l => l.status === 'active').length;
    pendingCount.innerText = allLicenses.filter(l => l.status === 'pending').length;
    blockedCount.innerText = allLicenses.filter(l => l.status === 'blocked').length;
    expiredCount.innerText = allLicenses.filter(l => l.status === 'expired').length;
    deletedCount.innerText = allLicenses.filter(l => l.status === 'deleted').length;
}

function renderLicenses() {
    tableBody.innerHTML = '';
    let filtered = allLicenses;
    if (currentFilter !== 'all') filtered = filtered.filter(l => l.status === currentFilter);
    if (currentSearch) {
        const s = currentSearch.toLowerCase();
        filtered = filtered.filter(l => l.key.toLowerCase().includes(s) || (l.deviceId && l.deviceId.toLowerCase().includes(s)));
    }
    filtered.forEach(item => {
        const expiry = item.expiryDate ? new Date(item.expiryDate.seconds * 1000).toLocaleDateString() : 'Not Activated';
        const extendBtn = item.status !== 'deleted'
            ? `<button class="btn-icon" onclick="window.extendKey('${item.id}')" title="Extend"><i class="fas fa-calendar-plus"></i></button>` : '';
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${item.key}</strong></td>
            <td><small>${item.deviceModel||'N/A'}</small><br><code>${item.deviceId ? item.deviceId.substring(0,8)+'...' : 'Unassigned'}</code></td>
            <td><span class="status-badge status-${item.status}">${item.status}</span></td>
            <td>${expiry}</td>
            <td>
                <button class="btn-icon" onclick="window.toggleBlock('${item.id}','${item.status}')" title="${item.status==='blocked'?'Unblock':'Block'}">
                    <i class="fas ${item.status==='blocked'?'fa-unlock':'fa-ban'}"></i></button>
                <button class="btn-icon" onclick="window.resetDevice('${item.id}')" title="Reset Device"><i class="fas fa-redo"></i></button>
                ${extendBtn}
                <button class="btn-icon delete" onclick="window.markDeleted('${item.id}')" title="Delete"><i class="fas fa-trash"></i></button>
            </td>`;
        tableBody.appendChild(row);
    });
}

function renderUsers() {
    usersTableBody.innerHTML = '';
    let filtered = allUsers;
    if (userSearch) {
        const s = userSearch.toLowerCase();
        filtered = filtered.filter(u => u.deviceId.toLowerCase().includes(s) ||
            (u.deviceModel && u.deviceModel.toLowerCase().includes(s)) ||
            (u.currentLicense && u.currentLicense.toLowerCase().includes(s)));
    }
    filtered.forEach(u => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${u.deviceModel||'Unknown'}</strong></td>
            <td>${u.deviceOS||'Unknown'}</td>
            <td><code>${u.currentLicense||'N/A'}</code></td>
            <td><small>${u.adminNotes||'No notes'}</small></td>
            <td><button class="btn-primary" style="padding:5px 10px;font-size:.7rem"
                onclick="window.openUserNoteModal('${u.deviceId}','${u.adminNotes||''}')">Note</button></td>`;
        usersTableBody.appendChild(row);
    });
}

function renderActivity(activities) {
    activityFeed.innerHTML = '';
    activities.forEach(act => {
        const item = document.createElement('div');
        item.className = 'activity-item';
        let icon = 'info-circle', color = '#3F51B5';
        const a = act.action.toLowerCase();
        if (a.includes('activated'))  { icon='check-circle';    color='#4caf50'; }
        else if (a.includes('generated'))  { icon='magic';          color='#9c27b0'; }
        else if (a.includes('blocked'))    { icon='ban';            color='#f44336'; }
        else if (a.includes('unblocked'))  { icon='unlock';         color='#2196f3'; }
        else if (a.includes('deleted'))    { icon='trash';          color='#000';    }
        else if (a.includes('reset'))      { icon='redo';           color='#ff9800'; }
        else if (a.includes('expired'))    { icon='clock';          color='#757575'; }
        else if (a.includes('extended'))   { icon='calendar-plus';  color='#009688'; }
        item.innerHTML = `
            <div class="activity-icon" style="background:${color}22;color:${color}"><i class="fas fa-${icon}"></i></div>
            <div style="flex-grow:1">
                <p>License <strong>${act.key}</strong>: ${act.action}</p>
                <small>${act.device} • ${act.timestamp ? new Date(act.timestamp.seconds*1000).toLocaleString() : 'Just now'}</small>
            </div>`;
        activityFeed.appendChild(item);
    });
}

// ── Misc bindings ─────────────────────────────────────────────────────────────
document.getElementById('genBtn').onclick       = window.handleGenerate;
document.getElementById('searchInput').oninput  = e => { currentSearch = e.target.value; renderLicenses(); };
document.getElementById('userSearchInput').oninput = e => { userSearch = e.target.value; renderUsers(); };
document.getElementById('logoutBtn').onclick    = () => { localStorage.removeItem('admin_session'); location.reload(); };