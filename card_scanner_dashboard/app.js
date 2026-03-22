import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
import { getFirestore, collection, addDoc, onSnapshot, serverTimestamp, query, orderBy, updateDoc, doc, deleteDoc, setDoc, getDocs, where, limit } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-firestore.js";

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

const ADMIN_PASS = "Ahmed.16021988";
let allLicenses = [];
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

// Auth Check
if (localStorage.getItem('admin_session') === 'true') { showDashboard(); }
document.getElementById('loginBtn').onclick = () => {
    if (document.getElementById('adminPass').value === ADMIN_PASS) {
        localStorage.setItem('admin_session', 'true');
        showDashboard();
    } else { document.getElementById('loginError').style.display = 'block'; }
};

function showDashboard() {
    document.getElementById('loginScreen').style.display = 'none';
    document.getElementById('dashboardContent').style.display = 'flex';
    startListeners();
}

// Tab Switching
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

// Stats Filtering
document.querySelectorAll('.stat-card.clickable').forEach(card => {
    card.onclick = () => {
        document.querySelectorAll('.stat-card.clickable').forEach(c => c.classList.remove('active'));
        card.classList.add('active');
        currentFilter = card.getAttribute('data-filter');
        renderLicenses();
    };
});

async function logActivity(key, action, device = "System") {
    await addDoc(collection(db, "activity"), {
        key: key,
        action: action,
        device: device,
        timestamp: serverTimestamp()
    });
}

function startListeners() {
    // Licenses Listener
    const qLic = query(collection(db, "licenses"), orderBy("createdAt", "desc"));
    onSnapshot(qLic, (snapshot) => {
        allLicenses = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        updateStats();
        renderLicenses();
        renderUsers();
    });

    // Activity Listener
    const qAct = query(collection(db, "activity"), orderBy("timestamp", "desc"), limit(50));
    onSnapshot(qAct, (snapshot) => {
        renderActivity(snapshot.docs.map(doc => doc.data()));
    });

    // Settings Listener
    onSnapshot(doc(db, "settings", "global"), (snap) => {
        if (snap.exists()) {
            const data = snap.data();
            // Don't overwrite the announcement field if user is typing
            if (document.activeElement !== document.getElementById('setting-announcement')) {
                document.getElementById('setting-announcement').value = data.announcement || '';
            }
            document.getElementById('setting-support').value = data.supportLink || '';
            document.getElementById('setting-killswitch').checked = data.killSwitch || false;
            document.getElementById('killSwitchStatus').innerText = data.killSwitch ? "APP IS DISABLED (KILL-SWITCH ON)" : "App is Live";
            document.getElementById('killSwitchStatus').style.color = data.killSwitch ? "red" : "green";
        }
    });
}

function updateStats() {
    totalCount.innerText = allLicenses.length;
    activeCount.innerText = allLicenses.filter(l => l.status === 'active').length;
    pendingCount.innerText = allLicenses.filter(l => l.status === 'pending').length;
    blockedCount.innerText = allLicenses.filter(l => l.status === 'blocked').length;
    expiredCount.innerText = allLicenses.filter(l => l.status === 'expired' || (l.expiryDate && new Date() > new Date(l.expiryDate.seconds * 1000))).length;
    deletedCount.innerText = allLicenses.filter(l => l.status === 'deleted').length;
}

function renderLicenses() {
    tableBody.innerHTML = '';
    let filtered = allLicenses;
    if (currentFilter !== 'all') filtered = allLicenses.filter(l => l.status === currentFilter);
    if (currentSearch) {
        const s = currentSearch.toLowerCase();
        filtered = filtered.filter(l => l.key.toLowerCase().includes(s) || (l.deviceId && l.deviceId.toLowerCase().includes(s)));
    }

    filtered.forEach(item => {
        const isExpired = item.expiryDate && new Date() > new Date(item.expiryDate.seconds * 1000);
        const displayStatus = isExpired ? 'expired' : item.status;
        const expiryDate = item.expiryDate ? new Date(item.expiryDate.seconds * 1000).toLocaleDateString() : 'Not Activated';
        
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${item.key}</strong></td>
            <td><small>${item.deviceModel || 'N/A'}</small><br><code>${item.deviceId ? item.deviceId.substring(0,8)+'...' : 'Unassigned'}</code></td>
            <td><span class="status-badge status-${displayStatus}">${displayStatus}</span></td>
            <td>${expiryDate}</td>
            <td>
                <button class="btn-icon" onclick="window.toggleBlock('${item.id}', '${item.status}')" title="${item.status === 'blocked' ? 'Unblock' : 'Block'}"><i class="fas ${item.status === 'blocked' ? 'fa-unlock' : 'fa-ban'}"></i></button>
                <button class="btn-icon" onclick="window.resetDevice('${item.id}')" title="Reset Device Link"><i class="fas fa-redo"></i></button>
                <button class="btn-icon delete" onclick="window.markDeleted('${item.id}')" title="Delete License"><i class="fas fa-trash"></i></button>
            </td>
        `;
        tableBody.appendChild(row);
    });
}

function renderUsers() {
    usersTableBody.innerHTML = '';
    let activated = allLicenses.filter(l => l.deviceId);
    if (userSearch) {
        const s = userSearch.toLowerCase();
        activated = activated.filter(u => u.key.toLowerCase().includes(s) || (u.deviceModel && u.deviceModel.toLowerCase().includes(s)));
    }
    activated.forEach(u => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${u.deviceModel || 'Unknown'}</strong></td>
            <td>${u.deviceOS || 'Unknown'}</td>
            <td><code>${u.key}</code></td>
            <td><small>${u.adminNotes || 'No notes'}</small></td>
            <td><button class="btn-primary" style="padding:5px 10px; font-size:0.7rem;" onclick="window.openNoteModal('${u.id}', '${u.adminNotes || ''}')">Note</button></td>
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
        if (action.includes('activated')) { icon = 'check-circle'; color = '#4caf50'; }
        else if (action.includes('generated')) { icon = 'magic'; color = '#9c27b0'; }
        else if (action.includes('blocked')) { icon = 'ban'; color = '#f44336'; }
        else if (action.includes('unblocked')) { icon = 'unlock'; color = '#2196f3'; }

        else if (action.includes('deleted')) { icon = 'trash'; color = '#000000'; }
        else if (action.includes('reset')) { icon = 'redo'; color = '#ff9800'; }
        
        item.innerHTML = `
            <div class="activity-icon" style="background: ${color}22; color: ${color}"><i class="fas fa-${icon}"></i></div>
            <div style="flex-grow: 1;">
                <p>License <strong>${act.key}</strong>: ${act.action}</p>
                <small>${act.device} • ${act.timestamp ? new Date(act.timestamp.seconds * 1000).toLocaleString() : 'Just now'}</small>
            </div>
        `;
        activityFeed.appendChild(item);
    });
}

// Global Dashboard Actions
window.toggleBlock = async (id, status) => {
    const lic = allLicenses.find(l => l.id === id);
    if (lic.status === 'deleted' || lic.status === 'expired') {
        alert("Deleted or Expired licenses cannot be modified.");
        return;
    }

    let newStatus;
    if (status === 'blocked') {
        // Unblocking
        // Check if this device is already using ANOTHER active license
        const deviceId = lic.deviceId;
        const otherActive = allLicenses.find(l => l.deviceId === deviceId && l.status === 'active' && l.id !== id);
        
        if (otherActive) {
            newStatus = 'pending'; // Device already has an active license, return this to pending
        } else {
            newStatus = deviceId ? 'active' : 'pending';
        }
        await logActivity(lic.key, "Unblocked", lic.deviceModel || "System");
    } else {
        // Blocking
        newStatus = 'blocked';
        await logActivity(lic.key, "Blocked", lic.deviceModel || "System");
    }
    await updateDoc(doc(db, "licenses", id), { status: newStatus });
};

window.resetDevice = async (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (lic.status === 'deleted' || lic.status === 'expired') {
        alert("Deleted or Expired licenses cannot be reset.");
        return;
    }
    if (confirm(`Reset device ID for ${lic.key}? User must re-activate.`)) {
        await logActivity(lic.key, "Reset device link", lic.deviceModel || "System");
        await updateDoc(doc(db, "licenses", id), { deviceId: "", deviceModel: "", deviceOS: "", status: "pending" });
    }
};

window.markDeleted = async (id) => {
    const lic = allLicenses.find(l => l.id === id);
    if (lic.status === 'deleted') return;
    if (confirm(`Permanently delete license ${lic.key}? This cannot be undone.`)) {
        await logActivity(lic.key, "Deleted license");
        await updateDoc(doc(db, "licenses", id), { status: 'deleted' });
    }
};

window.openNoteModal = (id, note) => {
    document.getElementById('noteModal').style.display = 'flex';
    document.getElementById('userNoteText').value = note;
    document.getElementById('saveNoteBtn').onclick = async () => {
        await updateDoc(doc(db, "licenses", id), { adminNotes: document.getElementById('userNoteText').value });
        document.getElementById('noteModal').style.display = 'none';
    };
};

// Global Settings saving
const saveGlobal = async (type) => {
    const announcementText = document.getElementById('setting-announcement').value;
    const supportLink = document.getElementById('setting-support').value;
    const killSwitch = document.getElementById('setting-killswitch').checked;

    const data = {
        announcement: announcementText,
        supportLink: supportLink,
        killSwitch: killSwitch,
        lastUpdated: serverTimestamp()
    };

    // If it's an announcement update, we might want to change its "ID" to trigger a popup on phones
    if (type === 'announcement') {
        data.announcementId = Date.now().toString();
    }

    await setDoc(doc(db, "settings", "global"), data, { merge: true });
    
    if (type === 'announcement') {
        document.getElementById('setting-announcement').value = ''; // Clear field after success
        alert("Announcement sent and field cleared!");
    } else {
        alert("Settings applied!");
    }
};

document.getElementById('saveAnnouncementBtn').onclick = () => saveGlobal('announcement');
document.getElementById('saveSupportBtn').onclick = () => saveGlobal('support');
document.getElementById('setting-killswitch').onchange = () => saveGlobal('killswitch');

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
            key, 
            deviceId: "", 
            status: "pending", 
            createdAt: serverTimestamp(), 
            activatedAt: null, 
            expiryDate: null 
        };
        
        if (durationVal === "3") docData.durationDays = 3; 
        else if (durationVal === "120") docData.lifetime = true; // Lifetime
        else docData.durationMonths = parseInt(durationVal);
        
        await addDoc(collection(db, "licenses"), docData);
        await logActivity(key, "Generated license");
    }
    
    document.getElementById('genBtn').disabled = false;
    document.getElementById('genBtn').innerText = "Generate & Save";
    document.getElementById('genModal').style.display = 'none';
};

document.getElementById('genBtn').onclick = window.handleGenerate;
document.getElementById('searchInput').oninput = (e) => { currentSearch = e.target.value; renderLicenses(); };
document.getElementById('userSearchInput').oninput = (e) => { userSearch = e.target.value; renderUsers(); };
window.logoutBtn = () => { localStorage.removeItem('admin_session'); location.reload(); };
document.getElementById('logoutBtn').onclick = window.logoutBtn;
window.showModal = () => document.getElementById('genModal').style.display = 'flex';
window.hideModal = () => document.getElementById('genModal').style.display = 'none';
