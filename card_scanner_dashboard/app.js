// Firebase Web SDK
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
import { getFirestore, collection, addDoc, onSnapshot, serverTimestamp, query, orderBy, updateDoc, doc, deleteDoc } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-firestore.js";

// TODO: Ensure your actual config is here
const firebaseConfig = {
    apiKey: "YOUR_API_KEY",
    authDomain: "card-scanner-1338a.firebaseapp.com",
    projectId: "card-scanner-1338a",
    storageBucket: "card-scanner-1338a.appspot.com",
    messagingSenderId: "YOUR_SENDER_ID",
    appId: "YOUR_APP_ID"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

const ADMIN_PASS = "Ahmed.16021988";
let allLicenses = [];

// DOM Elements
const tableBody = document.getElementById('tableBody');
const totalCount = document.getElementById('totalCount');
const activeCount = document.getElementById('activeCount');
const blockedCount = document.getElementById('blockedCount');
const genModal = document.getElementById('genModal');
const searchInput = document.getElementById('searchInput');
const loginScreen = document.getElementById('loginScreen');
const dashboardContent = document.getElementById('dashboardContent');
const adminPassInput = document.getElementById('adminPass');
const loginBtn = document.getElementById('loginBtn');
const loginError = document.getElementById('loginError');
const logoutBtn = document.getElementById('logoutBtn');

// Auth
if (localStorage.getItem('admin_session') === 'true') {
    showDashboard();
}

function handleLogin() {
    if (adminPassInput.value === ADMIN_PASS) {
        localStorage.setItem('admin_session', 'true');
        showDashboard();
    } else {
        loginError.style.display = 'block';
    }
}

function showDashboard() {
    loginScreen.style.display = 'none';
    dashboardContent.style.display = 'flex';
    startDataListener();
}

function handleLogout() {
    localStorage.removeItem('admin_session');
    location.reload();
}

loginBtn.onclick = handleLogin;
logoutBtn.onclick = handleLogout;
adminPassInput.onkeypress = (e) => { if(e.key === 'Enter') handleLogin(); };

window.showModal = () => genModal.style.display = 'flex';
window.hideModal = () => genModal.style.display = 'none';

function startDataListener() {
    const q = query(collection(db, "licenses"), orderBy("createdAt", "desc"));
    onSnapshot(q, (snapshot) => {
        allLicenses = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        renderTable(allLicenses);
        updateStats(allLicenses);
    });
}

function renderTable(data) {
    tableBody.innerHTML = '';
    data.forEach(item => {
        const row = document.createElement('tr');
        const expiryDate = item.expiryDate ? new Date(item.expiryDate.seconds * 1000).toLocaleDateString() : '<i>Not Activated</i>';
        const createdDate = item.createdAt ? new Date(item.createdAt.seconds * 1000).toLocaleDateString() : 'N/A';
        
        row.innerHTML = `
            <td><strong>${item.key}</strong></td>
            <td><code>${item.deviceId || 'Unassigned'}</code></td>
            <td><span class="status-badge status-${item.status}">${item.status}</span></td>
            <td>${createdDate}</td>
            <td>${expiryDate}</td>
            <td>
                <button class="btn-icon" onclick="window.toggleBlock('${item.id}', '${item.status}')" title="Block/Unlock">
                    <i class="fas ${item.status === 'blocked' ? 'fa-unlock' : 'fa-ban'}"></i>
                </button>
                <button class="btn-icon delete" onclick="window.deleteKey('${item.id}')" title="Delete">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        tableBody.appendChild(row);
    });
}

function updateStats(data) {
    totalCount.innerText = data.length;
    activeCount.innerText = data.filter(l => l.status === 'active').length;
    blockedCount.innerText = data.filter(l => l.status === 'blocked').length;
}

window.handleGenerate = async () => {
    const prefix = document.getElementById('prefix').value.toUpperCase() || 'AL';
    const durationVal = document.getElementById('duration').value;
    const qty = parseInt(document.getElementById('qty').value);
    
    const genBtn = document.getElementById('genBtn');
    genBtn.disabled = true;
    genBtn.innerText = "Generating...";

    try {
        for (let i = 0; i < qty; i++) {
            const random = Math.random().toString(36).substring(2, 10).toUpperCase();
            const checksum = [...(prefix + random)].reduce((a, b) => a + b.charCodeAt(0), 0) % 10;
            const key = `${prefix}-${random}-${checksum}`;

            const docData = {
                key: key,
                deviceId: "",
                status: "pending",
                createdAt: serverTimestamp(),
                activatedAt: null,
                expiryDate: null
            };

            // Logic: Duration is either days (trial) or months
            if (durationVal === "3") {
                docData.durationDays = 3;
            } else {
                docData.durationMonths = parseInt(durationVal);
            }

            await addDoc(collection(db, "licenses"), docData);
        }
        hideModal();
    } catch (e) {
        alert("Error: " + e.message);
    } finally {
        genBtn.disabled = false;
        genBtn.innerText = "Generate & Save to Cloud";
    }
};

window.toggleBlock = async (id, currentStatus) => {
    const newStatus = currentStatus === 'blocked' ? (allLicenses.find(l => l.id === id).deviceId ? 'active' : 'pending') : 'blocked';
    await updateDoc(doc(db, "licenses", id), { status: newStatus });
};

window.deleteKey = async (id) => {
    if (confirm("Delete this license?")) {
        await deleteDoc(doc(db, "licenses", id));
    }
};

searchInput.oninput = (e) => {
    const term = e.target.value.toLowerCase();
    const filtered = allLicenses.filter(l => 
        l.key.toLowerCase().includes(term) || 
        (l.deviceId && l.deviceId.toLowerCase().includes(term))
    );
    renderTable(filtered);
};

document.getElementById('genBtn').onclick = window.handleGenerate;
window.showTab = (tab) => console.log("Tab", tab);
