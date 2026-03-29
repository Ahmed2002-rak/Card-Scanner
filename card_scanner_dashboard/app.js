import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
import {
    getFirestore, collection, addDoc, onSnapshot, serverTimestamp,
    query, orderBy, updateDoc, doc, deleteDoc, setDoc, getDocs,
    getDoc, where, limit, Timestamp
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-firestore.js";

// ✅ SECURITY FIX: Import Firebase Auth — replaces the old localStorage bypass
// Previously anyone could type localStorage.setItem('admin_session','true') in
// DevTools and get full dashboard access. Firebase Auth requires a real
// email + password that only you know, backed by Google's auth infrastructure.
import {
    getAuth,
    signInWithEmailAndPassword,
    signOut,
    onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-auth.js";

const firebaseConfig = {
    apiKey:            "AIzaSyASAi6G8sgsVW8GDAFTyA38RWlbUIZ0Fcw",
    authDomain:        "card-scanner-1338a.firebaseapp.com",
    projectId:         "card-scanner-1338a",
    storageBucket:     "card-scanner-1338a.firebasestorage.app",
    messagingSenderId: "300868355176",
    appId:             "1:300868355176:web:9e6eb811ddae19dd39e7dd"
};

const app  = initializeApp(firebaseConfig);
const db   = getFirestore(app);
const auth = getAuth(app);

// ✅ SECURITY: Only this UID can access the dashboard.
// Even if someone creates a Firebase Auth account, they get rejected.
const ADMIN_UID = '4lnf9HCdVfX4Yl6BseD7kJvQK2j2';

let allLicenses   = [];
let allUsers      = [];
let currentFilter = 'all';
let currentSearch = '';
let userSearch    = '';

// ── XSS-safe text helper ─────────────────────────────────────────────────────
// Never use innerHTML with user data. This escapes HTML characters.
function esc(str) {
    const d = document.createElement('div');
    d.textContent = str ?? '';
    return d.innerHTML;
}

// ── DOM refs ──────────────────────────────────────────────────────────────────
const tableBody      = document.getElementById('tableBody');
const usersTableBody = document.getElementById('usersTableBody');
const activityFeed   = document.getElementById('activityFeed');
const totalCount     = document.getElementById('totalCount');
const activeCount    = document.getElementById('activeCount');
const pendingCount   = document.getElementById('pendingCount');
const blockedCount   = document.getElementById('blockedCount');
const expiredCount   = document.getElementById('expiredCount');
const deletedCount   = document.getElementById('deletedCount');

// ── Auth state — ADMIN-ONLY gate ─────────────────────────────────────────────
onAuthStateChanged(auth, (user) => {
    if (user && user.uid === ADMIN_UID) {
        showDashboard();
    } else {
        if (user) {
            // Someone logged in but is NOT admin — force logout
            signOut(auth);
            const err = document.getElementById('loginError');
            err.textContent = 'Access denied. This account is not authorized.';
            err.style.display = 'block';
        }
        document.getElementById('loginScreen').style.display    = 'flex';
        document.getElementById('dashboardContent').style.display = 'none';
    }
});

// ── Login ─────────────────────────────────────────────────────────────────────
document.getElementById('loginBtn').onclick = async () => {
    const email    = document.getElementById('adminEmail').value.trim();
    const password = document.getElementById('adminPass').value;
    const errorEl  = document.getElementById('loginError');
    const btn      = document.getElementById('loginBtn');

    if (!email || !password) {
        errorEl.textContent      = 'Please enter your email and password.';
        errorEl.style.display    = 'block';
        return;
    }

    btn.disabled  = true;
    btn.innerText = 'Signing in...';
    errorEl.style.display = 'none';

    try {
        // Firebase Auth validates credentials server-side.
        // No Firestore read needed, no password stored in the database.
        await signInWithEmailAndPassword(auth, email, password);
        // onAuthStateChanged above will fire and call showDashboard()
    } catch (e) {
        let msg = 'Invalid email or password.';
        if (e.code === 'auth/invalid-email')         msg = 'Please enter a valid email address.';
        if (e.code === 'auth/too-many-requests')     msg = 'Too many attempts. Please wait a few minutes.';
        if (e.code === 'auth/network-request-failed') msg = 'No internet connection.';
        errorEl.textContent   = msg;
        errorEl.style.display = 'block';
    } finally {
        btn.disabled  = false;
        btn.innerText = 'Unlock Dashboard';
    }
};

// Allow pressing Enter in password field to submit
document.getElementById('adminPass').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') document.getElementById('loginBtn').click();
});

// ── Logout ────────────────────────────────────────────────────────────────────
document.getElementById('logoutBtn').onclick = async () => {
    await signOut(auth);
    // onAuthStateChanged fires → shows login screen automatically
};

// ── Dashboard init ────────────────────────────────────────────────────────────
function showDashboard() {
    document.getElementById('loginScreen').style.display    = 'none';
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
    if (!lic) return alert("License not found.");
    if (lic.status !== 'active') return alert("Only active licenses can be extended.\nExpired or blocked keys cannot be extended — the customer needs a new key.");

    document.getElementById('extendModal').style.display = 'flex';

    const update = () => {
        const days      = parseInt(document.getElementById('extendDays').value) || 0;
        const base      = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
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
        const base      = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
        const newExpiry = new Date(base.getTime() + days * 86400000);
        const newStatus = lic.status; // stays active
        try {
            await updateDoc(doc(db, "licenses", id), {
                expiryDate: Timestamp.fromDate(newExpiry), status: newStatus
            });
            await logActivity(lic.key, `Extended by ${days} day${days === 1 ? '' : 's'}`, lic.deviceModel || "System");
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

window.showModal = () => document.getElementById('genModal').style.display = 'flex';
window.hideModal = () => document.getElementById('genModal').style.display = 'none';

window.handleGenerate = async () => {
    const prefix      = document.getElementById('prefix').value.toUpperCase() || 'RAK';
    const durationVal = document.getElementById('duration').value;
    const qty         = parseInt(document.getElementById('qty').value);
    if (qty < 1 || qty > 100) return;

    const btn      = document.getElementById('genBtn');
    btn.disabled   = true;
    btn.innerText  = "Generating...";

    for (let i = 0; i < qty; i++) {
        // ✅ Crypto-secure random key (replaces predictable Math.random)
        const arr = new Uint8Array(10);
        crypto.getRandomValues(arr);
        const random   = Array.from(arr, b => b.toString(36).padStart(2,'0')).join('').substring(0,12).toUpperCase();
        const checksum = [...(prefix + random)].reduce((a, b) => a + b.charCodeAt(0), 0) % 100;
        const key      = `${prefix}-${random}-${String(checksum).padStart(2,'0')}`;
        const docData  = {
            key, deviceId: "", status: "pending",
            createdAt: serverTimestamp(), activatedAt: null, expiryDate: null
        };
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

// ── Activity logging + auto-trim ──────────────────────────────────────────────

async function logActivity(key, action, device = "System") {
    try {
        await addDoc(collection(db, "activity"), {
            key, action, device, timestamp: serverTimestamp()
        });
        trimActivityLogs();
    } catch(e) { console.error("Log error:", e); }
}

async function trimActivityLogs() {
    try {
        const all = await getDocs(
            query(collection(db, "activity"), orderBy("timestamp", "asc"))
        );
        if (all.size > 100) {
            for (const d of all.docs.slice(0, all.size - 100)) await deleteDoc(d.ref);
        }
    } catch(e) { console.error("Trim error:", e); }
}

// ── Settings buttons ──────────────────────────────────────────────────────────
// NOTE: "Change Password" card is removed — passwords are now managed in
// Firebase Console → Authentication → Users. This is more secure.

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
        if (!confirm(isOn
            ? "⚠️ Enable Kill-Switch? ALL users will be blocked immediately."
            : "Re-enable app for all users?")) {
            e.target.checked = !isOn; return;
        }
        try {
            await setDoc(doc(db, "settings", "global"), { killSwitch: isOn }, { merge: true });
        } catch (e) { alert("Failed: " + e.message); e.target.checked = !isOn; }
    };

    // Update management
    document.getElementById('saveUpdateBtn').onclick = async () => {
        const latest      = document.getElementById('setting-latest-version').value.trim();
        const minVer      = document.getElementById('setting-min-version').value.trim();
        const apkUrl      = document.getElementById('setting-apk-url').value.trim();
        const updateNotes = document.getElementById('setting-update-notes').value.trim();

        if (!latest) return alert("Latest version is required (e.g. 1.0.1)");
        const vPattern = /^\d+\.\d+\.\d+$/;
        if (!vPattern.test(latest)) return alert("Version must be X.Y.Z format (e.g. 1.2.0)");
        if (minVer && !vPattern.test(minVer)) return alert("Min version must be X.Y.Z format");

        try {
            await setDoc(doc(db, "settings", "global"), {
                latestVersion: latest,
                minVersion:    minVer || latest,
                apkUrl:        apkUrl,
                updateNotes:   updateNotes
            }, { merge: true });
            alert(`✅ Update info saved!\nLatest: ${latest} | Min: ${minVer || latest}`);
        } catch (e) { alert("Failed: " + e.message); }
    };
}

// ── Realtime listeners ────────────────────────────────────────────────────────

function startListeners() {
    // Licenses
    onSnapshot(query(collection(db, "licenses"), orderBy("createdAt", "desc")), snap => {
        allLicenses = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        updateStats();
        renderLicenses();
    });

    // Users
    onSnapshot(query(collection(db, "users"), orderBy("lastActive", "desc")), snap => {
        allUsers = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        renderUsers();
    });

    // Activity
    onSnapshot(query(collection(db, "activity"), orderBy("timestamp", "desc"), limit(100)), snap => {
        renderActivity(snap.docs.map(d => d.data()));
    });

    // Settings
    onSnapshot(doc(db, "settings", "global"), snap => {
        if (!snap.exists()) return;
        const data = snap.data();
        if (document.activeElement !== document.getElementById('setting-announcement'))
            document.getElementById('setting-announcement').value = data.announcement || '';
        document.getElementById('setting-support').value      = data.supportLink   || '';
        document.getElementById('setting-killswitch').checked = data.killSwitch    || false;
        document.getElementById('killSwitchStatus').innerText =
            data.killSwitch ? "APP IS DISABLED (KILL-SWITCH ON)" : "App is Live";
        document.getElementById('killSwitchStatus').style.color =
            data.killSwitch ? "red" : "green";

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

// ── Render functions ──────────────────────────────────────────────────────────

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
        filtered = filtered.filter(l =>
            l.key.toLowerCase().includes(s) ||
            (l.deviceId && l.deviceId.toLowerCase().includes(s))
        );
    }
    filtered.forEach(item => {
        const expiry    = item.expiryDate
            ? new Date(item.expiryDate.seconds * 1000).toLocaleDateString()
            : 'Not Activated';
        const extendBtn = item.status === 'active'
            ? `<button class="btn-icon" onclick="window.extendKey('${esc(item.id)}')" title="Extend">
                   <i class="fas fa-calendar-plus"></i></button>` : '';
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${esc(item.key)}</strong></td>
            <td>
                <small>${esc(item.deviceModel || 'N/A')}</small><br>
                <code>${item.deviceId ? esc(item.deviceId.substring(0,8))+'...' : 'Unassigned'}</code>
            </td>
            <td><span class="status-badge status-${esc(item.status)}">${esc(item.status)}</span></td>
            <td>${esc(expiry)}</td>
            <td>
                <button class="btn-icon" onclick="window.toggleBlock('${esc(item.id)}','${esc(item.status)}')"
                    title="${item.status === 'blocked' ? 'Unblock' : 'Block'}">
                    <i class="fas ${item.status === 'blocked' ? 'fa-unlock' : 'fa-ban'}"></i>
                </button>
                <button class="btn-icon" onclick="window.resetDevice('${esc(item.id)}')" title="Reset Device">
                    <i class="fas fa-redo"></i>
                </button>
                ${extendBtn}
                <button class="btn-icon delete" onclick="window.markDeleted('${esc(item.id)}')" title="Delete">
                    <i class="fas fa-trash"></i>
                </button>
            </td>`;
        tableBody.appendChild(row);
    });
}

function renderUsers() {
    usersTableBody.innerHTML = '';
    let filtered = allUsers;
    if (userSearch) {
        const s = userSearch.toLowerCase();
        filtered = filtered.filter(u =>
            u.deviceId.toLowerCase().includes(s) ||
            (u.deviceModel && u.deviceModel.toLowerCase().includes(s)) ||
            (u.currentLicense && u.currentLicense.toLowerCase().includes(s))
        );
    }
    filtered.forEach(u => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${esc(u.deviceModel || 'Unknown')}</strong></td>
            <td>${esc(u.deviceOS || 'Unknown')}</td>
            <td><code>${esc(u.currentLicense || 'N/A')}</code></td>
            <td><small>${esc(u.adminNotes || 'No notes')}</small></td>
            <td>
                <button class="btn-primary" style="padding:5px 10px;font-size:.7rem"
                    onclick="window.openUserNoteModal('${esc(u.deviceId)}','${esc(u.adminNotes || '')}')">
                    Note
                </button>
            </td>`;
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
        if (a.includes('activated'))  { icon = 'check-circle';   color = '#4caf50'; }
        else if (a.includes('generated'))  { icon = 'magic';          color = '#9c27b0'; }
        else if (a.includes('blocked'))    { icon = 'ban';            color = '#f44336'; }
        else if (a.includes('unblocked'))  { icon = 'unlock';         color = '#2196f3'; }
        else if (a.includes('deleted'))    { icon = 'trash';          color = '#000';    }
        else if (a.includes('reset'))      { icon = 'redo';           color = '#ff9800'; }
        else if (a.includes('expired'))    { icon = 'clock';          color = '#757575'; }
        else if (a.includes('extended'))   { icon = 'calendar-plus';  color = '#009688'; }
        item.innerHTML = `
            <div class="activity-icon" style="background:${color}22;color:${color}">
                <i class="fas fa-${icon}"></i>
            </div>
            <div style="flex-grow:1">
                <p>License <strong>${esc(act.key)}</strong>: ${esc(act.action)}</p>
                <small>${esc(act.device)} • ${act.timestamp
                    ? new Date(act.timestamp.seconds * 1000).toLocaleString()
                    : 'Just now'}</small>
            </div>`;
        activityFeed.appendChild(item);
    });
}

// ── Event bindings ────────────────────────────────────────────────────────────
document.getElementById('genBtn').onclick          = window.handleGenerate;
document.getElementById('searchInput').oninput     = e => { currentSearch = e.target.value; renderLicenses(); };
document.getElementById('userSearchInput').oninput = e => { userSearch    = e.target.value; renderUsers(); };