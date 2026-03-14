/**
 * IRCord Landing Page - Server List
 *
 * Fetches and displays the list of public IRCord servers
 * Handles ircord:// protocol links for direct connections
 */

const DEFAULT_CONFIG = {
    DIRECTORY_URL: 'http://localhost:3000'
};

const RUNTIME_CONFIG = window.IRCORD_CONFIG || {};
const DIRECTORY_URL = normalizeBaseUrl(RUNTIME_CONFIG.DIRECTORY_URL || DEFAULT_CONFIG.DIRECTORY_URL);

function normalizeBaseUrl(url) {
    return String(url || '').replace(/\/+$/, '');
}

async function fetchServers() {
    const loadingEl = document.getElementById('servers-loading');
    const errorEl = document.getElementById('servers-error');
    const listEl = document.getElementById('servers-list');

    try {
        const response = await fetch(`${DIRECTORY_URL}/api/servers`);

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        loadingEl.style.display = 'none';

        if (data.servers && data.servers.length > 0) {
            renderServers(data.servers);
            listEl.style.display = 'grid';
        } else {
            listEl.innerHTML = `
                <div class="server-card empty">
                    <p>No public servers available at the moment.</p>
                    <p><a href="#host">Be the first to host one!</a></p>
                </div>
            `;
            listEl.style.display = 'grid';
        }
    } catch (error) {
        console.error('Failed to fetch servers:', error);
        loadingEl.style.display = 'none';
        errorEl.style.display = 'block';
    }
}

function renderServers(servers) {
    const listEl = document.getElementById('servers-list');

    const html = servers.map((server) => {
        const statusClass = server.online ? 'online' : 'offline';
        const statusText = server.online ? 'Online' : 'Offline';
        const connectUrl = `ircord://${server.host}:${server.port}`;

        return `
            <div class="server-card ${statusClass}">
                <div class="server-header">
                    <h3 class="server-name">${escapeHtml(server.name)}</h3>
                    <span class="server-status ${statusClass}">${statusText}</span>
                </div>
                <p class="server-description">${escapeHtml(server.description)}</p>
                <div class="server-meta">
                    <code class="server-address">${escapeHtml(server.host)}:${server.port}</code>
                </div>
                <div class="server-actions">
                    <a href="${connectUrl}" class="btn btn-connect" data-host="${escapeHtml(server.host)}" data-port="${server.port}">
                        Connect
                    </a>
                    <button class="btn btn-copy" data-address="${escapeHtml(server.host)}:${server.port}" title="Copy address">
                        Copy
                    </button>
                </div>
            </div>
        `;
    }).join('');

    listEl.innerHTML = html;

    document.querySelectorAll('.btn-copy').forEach((btn) => {
        btn.addEventListener('click', handleCopy);
    });

    document.querySelectorAll('.btn-connect').forEach((btn) => {
        btn.addEventListener('click', handleConnect);
    });
}

function handleCopy(event) {
    const button = event.currentTarget;
    const address = button.dataset.address;
    navigator.clipboard.writeText(address).then(() => {
        const originalText = button.textContent;
        button.textContent = 'Copied!';
        setTimeout(() => {
            button.textContent = originalText;
        }, 2000);
    });
}

function handleConnect(event) {
    const button = event.currentTarget;
    const host = button.dataset.host;
    const port = button.dataset.port;
    const url = `ircord://${host}:${port}`;

    window.location.href = url;

    setTimeout(() => {
        if (document.hidden) {
            return;
        }

        showProtocolHelp(host, port);
    }, 500);

    if (event) {
        event.preventDefault();
    }
}

function showProtocolHelp(host, port) {
    const serverAddress = host && port ? `${host}:${port}` : '';

    const helpHtml = `
        <div class="modal-overlay" id="protocol-modal">
            <div class="modal">
                <h3>Connect to IRCord Server</h3>
                <p>The IRCord protocol handler is not installed on your system.</p>

                <div class="modal-options">
                    <div class="modal-option">
                        <h4>Option 1: Download IRCord</h4>
                        <p>Download and install the IRCord client for the best experience.</p>
                        <a href="#download" class="btn" onclick="closeModal()">Go to Downloads</a>
                    </div>

                    <div class="modal-option">
                        <h4>Option 2: Connect Manually</h4>
                        <p>Use this address in your IRCord client:</p>
                        <code class="address-box">${serverAddress || 'host:port'}</code>
                        <button class="btn btn-copy-manual" onclick="copyManualAddress(this)">Copy Address</button>
                    </div>
                </div>

                <button class="modal-close" onclick="closeModal()">&times;</button>
            </div>
        </div>
    `;

    document.body.insertAdjacentHTML('beforeend', helpHtml);
}

function closeModal() {
    const modal = document.getElementById('protocol-modal');
    if (modal) {
        modal.remove();
    }
}

function copyManualAddress(button) {
    const addressBox = button.previousElementSibling;
    const address = addressBox.textContent;
    navigator.clipboard.writeText(address).then(() => {
        const originalText = button.textContent;
        button.textContent = 'Copied!';
        setTimeout(() => {
            button.textContent = originalText;
        }, 2000);
    });
}

function handleQuickConnect() {
    const addressInput = document.getElementById('server-address');
    const connectBtn = document.getElementById('connect-btn');

    connectBtn.addEventListener('click', () => {
        const address = addressInput.value.trim();
        if (!address) {
            return;
        }

        let host;
        let port;
        if (address.includes(':')) {
            const parts = address.split(':');
            host = parts[0];
            port = parseInt(parts[1], 10);
        } else {
            host = address;
            port = 6697;
        }

        if (!host || Number.isNaN(port)) {
            alert('Invalid address format. Use: host:port or just host');
            return;
        }

        window.location.href = `ircord://${host}:${port}`;

        setTimeout(() => {
            if (!document.hidden) {
                showProtocolHelp(host, port);
            }
        }, 500);
    });

    addressInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            connectBtn.click();
        }
    });
}

function handleProtocolRegistration() {
    const link = document.getElementById('protocol-handler');
    if (!link) {
        return;
    }

    link.addEventListener('click', (e) => {
        e.preventDefault();

        if ('registerProtocolHandler' in navigator) {
            alert('To register the ircord:// protocol, please install the IRCord desktop client.');
        } else {
            alert('Protocol handler registration requires the IRCord desktop client. Please download it from the Downloads section.');
        }
    });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function parseUrlParams() {
    const hash = window.location.hash;
    if (hash.startsWith('#connect=')) {
        const address = decodeURIComponent(hash.substring(9));
        const addressInput = document.getElementById('server-address');
        if (addressInput) {
            addressInput.value = address;
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    fetchServers();
    handleQuickConnect();
    handleProtocolRegistration();
    parseUrlParams();

    setInterval(fetchServers, 60000);
});
