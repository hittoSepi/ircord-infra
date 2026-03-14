# IRCord Web Client

A lightweight web-based interface for connecting to IRCord servers. This serves as a fallback when the native IRCord client isn't installed.

## Features

- **Quick Connect**: Enter a server address and connect directly
- **Public Server List**: Browse and connect to public IRCord servers
- **Protocol Handler Detection**: Tries to open the native IRCord client via `ircord://` protocol
- **Fallback Instructions**: Shows manual connection steps if the native client isn't installed
- **Copy-to-Clipboard**: Easy server address copying

## Usage

### Direct Connection
```
https://web.ircord.dev/?server=chat.example.com&port=6697&connect=true
```

Parameters:
- `server` - Server hostname (required)
- `port` - Server port (optional, defaults to 6697)
- `connect` - Auto-connect on page load (optional)

### As Fallback from Landing Page

When a user clicks an `ircord://` link but doesn't have the native client:

1. Landing page redirects to web client
2. Web client attempts to open the protocol handler
3. If that fails, shows manual connection instructions

## Deployment

This is a static web application. Deploy to any static hosting:

```bash
# Build (nothing to build, just static files)
# Deploy
cp -r ircord-webclient/* /var/www/web.ircord.dev/
```

Or use a simple HTTP server for testing:

```bash
cd ircord-webclient
python3 -m http.server 8080
# Open http://localhost:8080
```

## Configuration

Edit `app.js` to change the directory service URL:

```javascript
const DIRECTORY_URL = 'https://directory.ircord.dev';
```

## Browser Compatibility

- Chrome/Edge 80+
- Firefox 75+
- Safari 13.1+

Requires:
- Fetch API
- Clipboard API (for copy button)

## Integration with Landing Page

Add this to the landing page for fallback handling:

```javascript
// After protocol handler fails
window.location.href = `https://web.ircord.dev/?server=${host}&port=${port}`;
```

## Future Enhancements

- WebSocket proxy for browser-based IRCord connections
- WebRTC voice support
- End-to-end encryption in browser (using WebCrypto API)
