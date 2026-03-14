/**
 * IRCord Web Client
 * 
 * Provides a web-based interface for connecting to IRCord servers.
 * Falls back to manual connection instructions if the native client isn't installed.
 */

// Directory service URL
const DIRECTORY_URL = 'https://directory.ircord.dev';
// const DIRECTORY_URL = 'http://localhost:3001'; // For local testing

// DOM Elements
const serverInput = document.getElementById('server-input');
const connectBtn = document.getElementById('connect-btn');
const connectFeedback = document.getElementById('connect-feedback');
const serversLoading = document.getElementById('servers-loading');
const serversError = document.getElementById('servers-error');
const serversList = document.getElementById('servers-list');
const manualHelp = document.getElementById('manual-help');
const manualAddress = document.getElementById('manual-address');
const copyAddressBtn = document.getElementById('copy-address-btn');

/**
 * Parse URL parameters on page load
 */
function parseUrlParams() {
    const params = new URLSearchParams(window.location.search);
    const server = params.get('server');
    const port = params.get('port');
    
    if (server) {
        const fullAddress = port ? `${server}:${port}` : server;
        serverInput.value = fullAddress;
        
        // Auto-connect if requested
        if (params.get('connect') === 'true') {
            handleConnect();
        }
    }
}

/**
 * Handle connect button click
 */
function handleConnect() {
    const address = serverInput.value.trim();
    if (!address) {
        showFeedback('Please enter a server address', 'error');
        return;
    }
    
    // Parse address
    let host, port;
    if (address.includes(':')) {
        const parts = address.split(':');
        host = parts[0];
        port = parseInt(parts[1], 10);
    } else {
        host = address;
        port = 6697;
    }
    
    if (!host || isNaN(port)) {
        showFeedback('Invalid address format. Use: host:port', 'error');
        return;
    }
    
    // Try to open with protocol handler
    const protocolUrl = `ircord://${host}:${port}`;
    
    showFeedback('Opening IRCord client...', 'info');
    
    // Try to open the protocol
    window.location.href = protocolUrl;
    
    // Check if protocol worked after a delay
    setTimeout(() => {
        if (!document.hidden) {
            // Protocol didn't work, show manual help
            showManualHelp(host, port);
        }
    }, 1000);
}

/**
 * Show manual connection help
 */
function showManualHelp(host, port) {
    manualAddress.textContent = `${host}:${port}`;
    manualHelp.style.display = 'block';
    connectFeedback.style.display = 'none';
    
    // Scroll to manual help
    manualHelp.scrollIntoView({ behavior: 'smooth' });
}

/**
 * Show feedback message
 */
function showFeedback(message, type) {
    connectFeedback.textContent = message;
    connectFeedback.className = `feedback show ${type}`;
}

/**
 * Copy address to clipboard
 */
async function copyAddress() {
    const address = manualAddress.textContent;
    try {
        await navigator.clipboard.writeText(address);
        const originalText = copyAddressBtn.textContent;
        copyAddressBtn.textContent = 'Copied!';
        setTimeout(() => {
            copyAddressBtn.textContent = originalText;
        }, 2000);
    } catch (err) {
        console.error('Failed to copy:', err);
    }
}

/**
 * Fetch public servers from directory
 */
async function fetchServers() {
    try {
        const response = await fetch(`${DIRECTORY_URL}/api/servers`);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        
        const data = await response.json();
        
        serversLoading.style.display = 'none';
        
        if (data.servers && data.servers.length > 0) {
            renderServers(data.servers);
            serversList.style.display = 'flex';
        } else {
            serversList.innerHTML = '<p class="description">No public servers available.</p>';
            serversList.style.display = 'flex';
        }
    } catch (error) {
        console.error('Failed to fetch servers:', error);
        serversLoading.style.display = 'none';
        serversError.style.display = 'block';
    }
}

/**
 * Render server list
 */
function renderServers(servers) {
    const html = servers.map(server => {
        const isOnline = server.online;
        const statusClass = isOnline ? 'online' : 'offline';
        const statusText = isOnline ? 'Online' : 'Offline';
        
        return `
            <div class="server-item ${statusClass}">
                <div class="server-info">
                    <h3>${escapeHtml(server.name)}</h3>
                    <p>${escapeHtml(server.description)}</p>
                </div>
                <div class="server-meta">
                    <div class="server-address">${escapeHtml(server.host)}:${server.port}</div>
                    <span class="status-badge ${statusClass}">${statusText}</span>
                </div>
            </div>
        `;
    }).join('');
    
    serversList.innerHTML = html;
    
    // Add click handlers to server items
    document.querySelectorAll('.server-item').forEach((item, index) => {
        item.style.cursor = 'pointer';
        item.addEventListener('click', () => {
            const server = servers[index];
            serverInput.value = `${server.host}:${server.port}`;
            handleConnect();
        });
    });
}

/**
 * Escape HTML special characters
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Initialize
 */
document.addEventListener('DOMContentLoaded', () => {
    // Parse URL parameters
    parseUrlParams();
    
    // Set up event listeners
    connectBtn.addEventListener('click', handleConnect);
    copyAddressBtn.addEventListener('click', copyAddress);
    
    // Allow Enter key to submit
    serverInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            handleConnect();
        }
    });
    
    // Fetch server list
    fetchServers();
});
