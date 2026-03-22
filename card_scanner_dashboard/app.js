import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
// ✅ Added: getDoc (for password fetch), Timestamp (for extend key date math)
import { getFirestore, collection, addDoc, onSnapshot, serverTimestamp, query, orderBy, updateDoc, doc, deleteDoc, setDoc, getDocs, getDoc, where, limit, Timestamp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-firestore.js";

const firebaseConfig = {
    apiKey: "AIzaSyBfnO29PNacfCnUMSHBPyOze-H5wt80D-g",
    authDomain: "card-scanner-1338a.firebaseapp.com",
    projectId: "card-scanner-1338a",
    storageBucket: "card-scanner-1338a.firebasestorage.app",
    messagingSenderId: "300868355176",
    appId: "1:300868355176:web:9e6eb811ddae19dd39e7dd"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

// ✅ REMOVED: hardcoded ADMIN_PASS — password now lives in Firestore settings/global.adminPassword
let allLicenses = [];
let allUsers = [];
let currentFilter = 'all';
let currentSearch = '';
let userSearch = '';

// DOM Elements
const tableBody = document.getElementById('tableBody');
const usersTableBody = document.getElementById('usersTableBody');
const activityFeed = document.getElementById('activityFeed');
const totalCount = document.getElementById('totalCount');
const activeCount = document.getElementById('activeCount');
const pendingCount = document.getElementById('pendingCount');
const blockedCount = document.getElementById('blockedCount');
const expiredCount = document.getElementById('expiredCount');
const deletedCount = document.getElementById('deletedCount');

// ─── License Actions ──────────────────────────────────────────────────────────

window.toggleBlock = async (id, status) => {
    try {
        const lic = allLicenses.find(l => l.id === id);
        if (!lic) { alert("Error: License not found in local cache."); return; }
        if (lic.status === 'deleted' || lic.status === 'expired') {
            alert("Deleted or Expired licenses cannot be modified.");
            return;
        }
        let newStatus;
        if (status === 'blocked') {
            newStatus = lic.deviceId ? 'active' : 'pending';
            await logActivity(lic.key, "Unblocked", lic.deviceModel || "System");
        } else {
            newStatus = 'blocked';
            await logActivity(lic.key, "Blocked", lic.deviceModel || "System");
        }
        await updateDoc(doc(db, "licenses", id), { status: newStatus });
    } catch (e) {
        console.error("Toggle Block Error:", e);
        alert("Failed to toggle status: " + e.message);
    }
};

window.resetDevice = async (id) => {
    try {
        const lic = allLicenses.find(l => l.id === id);
        if (!lic) { alert("Error: License not found in local cache."); return; }
        if (lic.status === 'deleted' || lic.status === 'expired') {
            alert("Deleted or Expired licenses cannot be reset.");
            return;
        }
        if (confirm(`Reset device ID for ${lic.key}? User must re-activate.`)) {
            await logActivity(lic.key, "Reset device link", lic.deviceModel || "System");
            await updateDoc(doc(db, "licenses", id), {
                deviceId: "", deviceModel: "", deviceOS: "", status: "pending"
            });
        }
    } catch (e) {
        console.error("Reset Device Error:", e);
        alert("Failed to reset device: " + e.message);
    }
};

window.markDeleted = async (id) => {
    try {
        const lic = allLicenses.find(l => l.id === id);
        if (!lic) { alert("Error: License not found in local cache."); return; }
        if (lic.status === 'deleted') return;
        if (confirm(`Permanently delete license ${lic.key}? This cannot be undone.`)) {
            await logActivity(lic.key, "Deleted license");
            // Clear deviceId so this doc never matches a device's stream again
            await updateDoc(doc(db, "licenses", id), {
                status: 'deleted', deviceId: "", deviceModel: "", deviceOS: ""
            });
        }
    } catch (e) {
        console.error("Delete Error:", e);
        alert("Failed to delete license: " + e.message);
    }
};

// ✅ NEW: Extend key — adds days on top of current expiry date
window.extendKey = (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (!lic) return;
    if (lic.status === 'deleted') {
        alert("Cannot extend a deleted license.");
        return;
    }

    const modal = document.getElementById('extendModal');
    modal.style.display = 'flex';

    const updatePreview = () => {
        const days = parseInt(document.getElementById('extendDays').value);
        const base = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
        const newExpiry = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
        document.getElementById('extendCurrentExpiry').textContent =
            `Current expiry: ${lic.expiryDate ? base.toLocaleDateString() : 'Not yet activated'}`;
        document.getElementById('extendNewExpiry').textContent =
            `New expiry after extension: ${newExpiry.toLocaleDateString()}`;
    };

    document.getElementById('extendDays').oninput = updatePreview;
    updatePreview();

    document.getElementById('confirmExtendBtn').onclick = async () => {
        const days = parseInt(document.getElementById('extendDays').value);
        if (!days || days < 1) { alert("Please enter a valid number of days."); return; }

        const base = lic.expiryDate ? new Date(lic.expiryDate.seconds * 1000) : new Date();
        const newExpiry = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);

        // If key was expired, restore it to the correct status
        let statusUpdate = lic.status;
        if (lic.status === 'expired') {
            statusUpdate = lic.deviceId ? 'active' : 'pending';
        }

        try {
            await updateDoc(doc(db, "licenses", id), {
                expiryDate: Timestamp.fromDate(newExpiry),
                status: statusUpdate
            });
            await logActivity(lic.key, `Extended by ${days} day${days === 1 ? '' : 's'}`, lic.deviceModel || "System");
            modal.style.display = 'none';
            alert(`✅ License extended to ${newExpiry.toLocaleDateString()}`);
        } catch (e) {
            alert("Failed to extend license: " + e.message);
        }
    };
};

window.hideExtendModal = () => {
    document.getElementById('extendModal').style.display = 'none';
};

window.openUserNoteModal = (deviceId, note) => {
    document.getElementById('noteModal').style.display = 'flex';
    document.getElementById('userNoteText').value = note;
    document.getElementById('saveNoteBtn').onclick = async () => {
        try {
            await updateDoc(doc(db, "users", deviceId), {
                adminNotes: document.getElementById('userNoteText').value
            });
            document.getElementById('noteModal').style.display = 'none';
        } catch (e) {
            alert("Failed to save note: " + e.message);
        }
    };
};

window.showModal = () => document.getElementById('genModal').style.display = 'flex';
window.hideModal = () => document.getElementById('genModal').style.display = 'none';

window.handleGenerate = async () => {
    const prefix = document.getElementById('prefix').value.toUpperCase() || 'RAK';
    const durationVal = document.getElementById('duration').value;
    const qty = parseInt(document.getElementById('qty').value);
    if (qty < 1 || qty > 100) return;

    document.getElementById('genBtn').disabled = true;
    document.getElementById('genBtn').innerText = "Generating...";

    for (let i = 0; i < qty; i++) {
        const random = Math.random().toString(36).substring(2, 10).toUpperCase();
        const checksum = [...(prefix + random)].reduce((a, b) => a + b.charCodeAt(0), 0) % 10;
        const key = `${prefix}-${random}-${checksum}`;
        const docData = {
            key, deviceId: "", status: "pending",
            createdAt: serverTimestamp(), activatedAt: null, expiryDate: null
        };
        if (durationVal === "3") docData.durationDays = 3;
        else if (durationVal === "120") docData.lifetime = true;
        else docData.durationMonths = parseInt(durationVal);

        await addDoc(collection(db, "licenses"), docData);
        await logActivity(key, "Generated license");
    }

    document.getElementById('genBtn').disabled = false;
    document.getElementById('genBtn').innerText = "Generate & Save";
    document.getElementById('genModal').style.display = 'none';
};

// ─── Auth ─────────────────────────────────────────────────────────────────────

if (localStorage.getItem('admin_session') === 'true') {
    showDashboard();
}

// ✅ CHANGED: Password is now fetched from Firestore settings/global.adminPassword
// It is no longer hardcoded in this file.
// To change your password: go to Firestore → settings → global → edit adminPassword field.
document.getElementById('loginBtn').onclick = async () => {
    const entered = document.getElementById('adminPass').value;
    document.getElementById('loginBtn').disabled = true;
    document.getElementById('loginBtn').innerText = "Verifying...";

    try {
        const settingsSnap = await getDoc(doc(db, "settings", "global"));
        if (!settingsSnap.exists()) {
            alert("❌ Dashboard not configured. Please create settings/global in Firestore and add an adminPassword field.");
            return;
        }
        const correctPass = settingsSnap.data().adminPassword;
        if (!correctPass) {
            alert("❌ No admin password set. Add an adminPassword field to settings/global in Firestore.");
            return;
        }
        if (entered === correctPass) {
            localStorage.setItem('admin_session', 'true');
            showDashboard();
        } else {
            document.getElementById('loginError').style.display = 'block';
        }
    } catch (e) {
        alert("Failed to verify password. Check your internet connection.\n\n" + e.message);
    } finally {
        document.getElementById('loginBtn').disabled = false;
        document.getElementById('loginBtn').innerText = "Unlock Dashboard";
    }
};

function showDashboard() {
    document.getElementById('loginScreen').style.display = 'none';
    document.getElementById('dashboardContent').style.display = 'flex';
    startListeners();
    bindSettingsButtons();
}

// ─── Tab Switching ────────────────────────────────────────────────────────────

document.querySelectorAll('#mainNav a[data-tab]').forEach(link => {
    link.onclick = (e) => {
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

// ─── Activity Logging & Auto-Trim ─────────────────────────────────────────────

async function logActivity(key, action, device = "System") {
    try {
        await addDoc(collection(db, "activity"), {
            key, action, device, timestamp: serverTimestamp()
        });
        // ✅ NEW: Auto-trim activity to last 100 entries after every write
        trimActivityLogs();
    } catch(e) {
        console.error("Log Activity Error", e);
    }
}

// ✅ NEW: Keeps only the 100 most recent activity documents.
// Queries all docs ordered oldest-first, deletes any beyond the 100-entry cap.
async function trimActivityLogs() {
    try {
        const allDocs = await getDocs(
            query(collection(db, "activity"), orderBy("timestamp", "asc"))
        );
        if (allDocs.size > 100) {
            const excess = allDocs.docs.slice(0, allDocs.size - 100);
            for (const d of excess) {
                await deleteDoc(d.ref);
            }
        }
    } catch(e) {
        console.error("Trim activity error:", e);
    }
}

// ─── Settings Buttons ─────────────────────────────────────────────────────────

function bindSettingsButtons() {
    // Announcement
    document.getElementById('saveAnnouncementBtn').onclick = async () => {
        const text = document.getElementById('setting-announcement').value.trim();
        try {
            const newId = `ann_${Date.now()}`;
            await setDoc(doc(db, "settings", "global"), {
                announcement: text,
                announcementId: newId
            }, { merge: true });
            alert("Announcement saved! It will appear in all active apps.");
        } catch (e) {
            alert("Failed to save announcement: " + e.message);
        }
    };

    // Support link
    document.getElementById('saveSupportBtn').onclick = async () => {
        const link = document.getElementById('setting-support').value.trim();
        try {
            await setDoc(doc(db, "settings", "global"), { supportLink: link }, { merge: true });
            alert("Support link updated!");
        } catch (e) {
            alert("Failed to update support link: " + e.message);
        }
    };

    // Kill switch
    document.getElementById('setting-killswitch').onchange = async (e) => {
        const isOn = e.target.checked;
        const confirmed = confirm(
            isOn
                ? "⚠️ ENABLE KILL SWITCH? This will block ALL users immediately."
                : "Re-enable the app for all users?"
        );
        if (!confirmed) { e.target.checked = !isOn; return; }
        try {
            await setDoc(doc(db, "settings", "global"), { killSwitch: isOn }, { merge: true });
        } catch (e) {
            alert("Failed to update kill switch: " + e.message);
            e.target.checked = !isOn;
        }
    };

    // ✅ NEW: Change admin password from within the dashboard
    document.getElementById('savePasswordBtn').onclick = async () => {
        const newPass = document.getElementById('setting-password').value.trim();
        const confirm1 = document.getElementById('setting-password-confirm').value.trim();
        if (!newPass || newPass.length < 6) {
            alert("Password must be at least 6 characters.");
            return;
        }
        if (newPass !== confirm1) {
            alert("Passwords do not match.");
            return;
        }
        if (!confirm("Change admin password? You will need to use the new password next time.")) return;
        try {
            await setDoc(doc(db, "settings", "global"), { adminPassword: newPass }, { merge: true });
            document.getElementById('setting-password').value = '';
            document.getElementById('setting-password-confirm').value = '';
            alert("✅ Password changed successfully!");
        } catch (e) {
            alert("Failed to change password: " + e.message);
        }
    };
}

// ─── Realtime Listeners ───────────────────────────────────────────────────────

function startListeners() {
    // Licenses
    const qLic = query(collection(db, "licenses"), orderBy("createdAt", "desc"));
    onSnapshot(qLic, (snapshot) => {
        allLicenses = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
        updateStats();
        renderLicenses();
    });

    // Users
    const qUsers = query(collection(db, "users"), orderBy("lastActive", "desc"));
    onSnapshot(qUsers, (snapshot) => {
        allUsers = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
        renderUsers();
    });

    // Activity (display only — trim is handled separately)
    const qAct = query(collection(db, "activity"), orderBy("timestamp", "desc"), limit(100));
    onSnapshot(qAct, (snapshot) => {
        renderActivity(snapshot.docs.map(d => d.data()));
    });

    // Settings
    onSnapshot(doc(db, "settings", "global"), (snap) => {
        if (snap.exists()) {
            const data = snap.data();
            if (document.activeElement !== document.getElementById('setting-announcement')) {
                document.getElementById('setting-announcement').value = data.announcement || '';
            }
            document.getElementById('setting-support').value = data.supportLink || '';
            document.getElementById('setting-killswitch').checked = data.killSwitch || false;
            document.getElementById('killSwitchStatus').innerText =
                data.killSwitch ? "APP IS DISABLED (KILL-SWITCH ON)" : "App is Live";
            document.getElementById('killSwitchStatus').style.color =
                data.killSwitch ? "red" : "green";
        }
    });
}

// ─── Render Functions ─────────────────────────────────────────────────────────

function updateStats() {
    totalCount.innerText = allLicenses.length;
    activeCount.innerText = allLicenses.filter(l => l.status === 'active').length;
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
        const expiryDate = item.expiryDate
            ? new Date(item.expiryDate.seconds * 1000).toLocaleDateString()
            : 'Not Activated';

        // ✅ NEW: Extend button — hidden for deleted licenses (terminal state)
        const extendBtn = item.status !== 'deleted'
            ? `<button class="btn-icon" onclick="window.extendKey('${item.id}')" title="Extend License"><i class="fas fa-calendar-plus"></i></button>`
            : '';

        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${item.key}</strong></td>
            <td>
                <small>${item.deviceModel || 'N/A'}</small><br>
                <code>${item.deviceId ? item.deviceId.substring(0,8)+'...' : 'Unassigned'}</code>
            </td>
            <td><span class="status-badge status-${item.status}">${item.status}</span></td>
            <td>${expiryDate}</td>
            <td>
                <button class="btn-icon" onclick="window.toggleBlock('${item.id}', '${item.status}')" title="${item.status === 'blocked' ? 'Unblock' : 'Block'}">
                    <i class="fas ${item.status === 'blocked' ? 'fa-unlock' : 'fa-ban'}"></i>
                </button>
                <button class="btn-icon" onclick="window.resetDevice('${item.id}')" title="Reset Device Link">
                    <i class="fas fa-redo"></i>
                </button>
                ${extendBtn}
                <button class="btn-icon delete" onclick="window.markDeleted('${item.id}')" title="Delete License">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
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
            <td><strong>${u.deviceModel || 'Unknown'}</strong></td>
            <td>${u.deviceOS || 'Unknown'}</td>
            <td><code>${u.currentLicense || 'N/A'}</code></td>
            <td><small>${u.adminNotes || 'No notes'}</small></td>
            <td>
                <button class="btn-primary" style="padding:5px 10px; font-size:0.7rem;"
                    onclick="window.openUserNoteModal('${u.deviceId}', '${u.adminNotes || ''}')">
                    Note
                </button>
            </td>
        `;
        usersTableBody.appendChild(row);
    });
}

function renderActivity(activities) {
    activityFeed.innerHTML = '';
    activities.forEach(act => {
        const item = document.createElement('div');
        item.className = 'activity-item';
        let icon = 'info-circle', color = '#3F51B5';
        const action = act.action.toLowerCase();
        if (action.includes('activated'))  { icon = 'check-circle'; color = '#4caf50'; }
        else if (action.includes('generated')) { icon = 'magic';       color = '#9c27b0'; }
        else if (action.includes('blocked'))   { icon = 'ban';         color = '#f44336'; }
        else if (action.includes('unblocked')) { icon = 'unlock';      color = '#2196f3'; }
        else if (action.includes('deleted'))   { icon = 'trash';       color = '#000000'; }
        else if (action.includes('reset'))     { icon = 'redo';        color = '#ff9800'; }
        else if (action.includes('expired'))   { icon = 'clock';       color = '#757575'; }
        else if (action.includes('extended'))  { icon = 'calendar-plus'; color = '#009688'; } // ✅ NEW
        item.innerHTML = `
            <div class="activity-icon" style="background:${color}22; color:${color}">
                <i class="fas fa-${icon}"></i>
            </div>
            <div style="flex-grow:1;">
                <p>License <strong>${act.key}</strong>: ${act.action}</p>
                <small>${act.device} • ${act.timestamp ? new Date(act.timestamp.seconds * 1000).toLocaleString() : 'Just now'}</small>
            </div>
        `;
        activityFeed.appendChild(item);
    });
}

// ─── Event Bindings ───────────────────────────────────────────────────────────

document.getElementById('genBtn').onclick = window.handleGenerate;
document.getElementById('searchInput').oninput = (e) => { currentSearch = e.target.value; renderLicenses(); };
document.getElementById('userSearchInput').oninput = (e) => { userSearch = e.target.value; renderUsers(); };
document.getElementById('logoutBtn').onclick = () => { localStorage.removeItem('admin_session'); location.reload(); };