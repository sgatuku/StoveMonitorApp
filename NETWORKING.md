## 🧩 Networking Overview

**Components**
- Raspberry Pi (with camera module)
- Your registered domain (e.g. `example.com`)
- Cloudflare account (free tier)
- Mobile app (e.g. built in Flutter)
- Home Wi-Fi connection

**Workflow**
1. The Pi hosts a local HTTP server (e.g. Flask/FastAPI) that exposes endpoints like:
   - `GET /stove_state` → returns whether the stove is on/off.
   - `POST /status` → (optional) accepts geofence updates from the mobile app.
2. Cloudflare Tunnel exposes this Pi service securely to the internet.
3. The mobile app calls the public domain (e.g. `https://stove.example.com/stove_state`) when you’re away from home.

---

## ⚙️ Step-by-Step Setup

### 1. Buy a Domain and Set Up Cloudflare
1. Buy any cheap domain (e.g. from Namecheap, Google Domains, etc.).
2. Create a free [Cloudflare account](https://dash.cloudflare.com/).
3. Add your domain to Cloudflare and update the nameservers to the ones Cloudflare gives you.
4. Once verified, you’ll be able to manage DNS directly in Cloudflare.



### 2. Create a Tunnel in Cloudflare

Go to Cloudflare Dashboard → Zero Trust → Tunnels → Create Tunnel.

Name it (e.g., pi-tunnel) and choose “Cloudflared installed on this machine”.

Copy the one-line command Cloudflare shows you.

Run the Command on the Raspberry Pi

```cloudflared service install https://setup.cloudflare.com/<unique-id>```


This automatically registers and connects your Pi.

### 5. Expose the Local Web Service

In Cloudflare Dashboard → Tunnels → your tunnel → Public Hostnames → Add:

Subdomain: api.example.com

Service Type: HTTP

URL: http://localhost:5000

### 6. Access from Anywhere

Your Pi’s API is now securely reachable at:

https://api.example.com


Cloudflare provides HTTPS + DDoS protection automatically.

### 7. Optional: Restrict Access

For private access (only your phone/app):

Go to Access → Applications → Add Application → Self-hosted.

Choose your subdomain (api.example.com) and require a login or device certificate.