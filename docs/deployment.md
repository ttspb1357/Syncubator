# Deployment

How to take Syncubator from a fresh Raspberry Pi to a running incubator: backend, HTTPS, touchscreen kiosk, the app
build, and optionally the public website.

Wire the hardware first (see [hardware.md](hardware.md)).

## 1. Raspberry Pi setup

Raspberry Pi 4 with Raspberry Pi OS (64-bit) and Python 3.11 or newer.

```bash
sudo apt update
sudo apt install -y python3-dev python3-venv i2c-tools nginx chromium
sudo raspi-config          # Interface Options -> I2C -> Enable
sudo usermod -aG gpio,i2c,video $USER      # then log out and in again
i2cdetect -y 1             # expect 0x29, 0x40, 0x48, 0x49, 0x4a, 0x77 for the connected sensors
```

Give the Pi a fixed IP address (the HTTPS certificate is tied to it):

```bash
nmcli connection show
sudo nmcli connection modify "<connection-name>" ipv4.addresses <pi-ip>/24 ipv4.gateway <router-ip> \
  ipv4.dns "1.1.1.1,8.8.8.8" ipv4.method manual
sudo nmcli connection down "<connection-name>" && sudo nmcli connection up "<connection-name>"
```

## 2. Backend

```bash
git clone <this-repository> ~/syncubator
cp -r ~/syncubator/raspberry_pi ~/syncubator_app
cd ~/syncubator_app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 app.py             # manual test: look for [OK] lines, then Ctrl+C
```

Open `http://<pi-ip>:5000/status` from another device while it runs: the JSON should contain live (non-zero) readings.

`app.py` has a few values to check for your build:

| Setting | Where | Meaning |
|---|---|---|
| `CAL_FACTORS`, `ZERO_OFFSETS` | `app.py` | Load-cell calibration: zero on the empty platform, scale against a known mass |
| `O2_V_ZERO`, `O2_V_AIR` | `app.py` | Oxygen cell two-point calibration (0 V is 0 %, about 1.4 V is 20.9 %) |
| `SKIN_R_REF` | `app.py` | The **measured** resistance of the skin-probe divider resistor (about 11 kohm) |
| `RELAY_ACTIVE_LOW` | `app.py` | True for the usual relay boards: confirm yours before wiring mains loads |

Set points, alarm limits and monitoring switches are changed from the app and saved to `config.json`.

## 3. HTTPS certificate and Nginx

```bash
openssl req -x509 -nodes -newkey rsa:2048 -keyout syncubator.key -out syncubator.crt -days 3650 \
  -subj "/CN=<pi-ip>" -addext "subjectAltName=IP:<pi-ip>"
sudo mkdir -p /etc/nginx/ssl && sudo mv syncubator.crt syncubator.key /etc/nginx/ssl/
sudo chmod 600 /etc/nginx/ssl/syncubator.key
```

The `subjectAltName` is required: modern TLS clients, including Flutter, reject CN-only certificates. Never share or
commit the `.key` file.

```bash
sudo cp ~/syncubator_app/deploy/nginx_syncubator.conf /etc/nginx/sites-available/syncubator
sudo ln -s /etc/nginx/sites-available/syncubator /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
# edit server_name in the file: replace 192.168.0.116 with your Pi's address
sudo nginx -t && sudo systemctl reload nginx
```

## 4. Backend service

```bash
sudo cp ~/syncubator_app/deploy/syncubator.service /etc/systemd/system/syncubator.service
# edit User= and the two paths in the file if your user is not "pi" or the folder is not ~/syncubator_app
sudo systemctl daemon-reload
sudo systemctl enable --now syncubator.service
sudo systemctl status syncubator.service        # active (running)
sudo journalctl -u syncubator.service -f        # live log
```

Gunicorn is bound to `127.0.0.1:5000` on purpose: the API is reachable only through Nginx over HTTPS. Do not change it to
`0.0.0.0`.

Verify the whole chain:

```bash
curl -s --max-time 3 http://<pi-ip>:5000/status    # must FAIL: port 5000 is local only
curl -sk https://<pi-ip>/status                     # returns live JSON
```

## 5. Build and install the app

Demo mode is the default. Real builds turn it off with `--dart-define=USE_MOCK_DATA=false`.

**Web build for the touchscreen kiosk (and the public website):**

```bash
flutter build web --release --pwa-strategy=none \
  --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=
scp -r build/web/* pi@<pi-ip>:/tmp/web/
ssh pi@<pi-ip> 'sudo rm -rf /var/www/html/* && sudo cp -r /tmp/web/* /var/www/html/'
```

An empty `API_BASE_URL` makes the web app call whatever origin it was loaded from, so one build works on the kiosk
(`https://127.0.0.1`) and on the public site. `--pwa-strategy=none` stops browsers keeping an old build.

**Android app:** copy your Pi's certificate to `assets/certs/syncubator.crt` (the app trusts exactly that certificate),
then

```bash
flutter build apk --release --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=https://<pi-ip>
```

## 6. Touchscreen kiosk

```bash
mkdir -p ~/.config/autostart
cp ~/syncubator_app/deploy/syncubator_kiosk.desktop ~/.config/autostart/
sudo reboot
```

Chromium starts full screen on `https://127.0.0.1` at login. A long press on the app header icon closes the kiosk to
reach the desktop (served only to the incubator's own screen).

## 7. Public website (optional)

The dashboard can be reached from anywhere through a Cloudflare Tunnel, with a login in front of it. No inbound port is
opened on the incubator's network.

1. Add your domain to Cloudflare. In Zero Trust, create a tunnel and add a public hostname pointing at
   `https://127.0.0.1:443` with "No TLS Verify" on (the Pi's certificate is self-signed).
2. Add an Access application on that hostname with an e-mail one-time-PIN policy listing the people allowed in.
3. Install the connector on the Pi from Cloudflare's apt repository, then register it with the token from the dashboard
   (`sudo cloudflared service install <TOKEN>`). **Never commit the token.**
4. If your network blocks UDP 7844 (QUIC), force TCP: put `Environment=TUNNEL_TRANSPORT_PROTOCOL=http2` in a
   `cloudflared.service.d/http2.conf` drop-in.
5. Optional: deploy `deploy/cloudflare_offline_worker.js` as a Worker routed on the site root only, to show an
   "incubator offline" page when the Pi is down. Do not route it on API paths: `/status` is polled every second.

The static information page in [`website/`](../website/) can be hosted on Cloudflare Pages (or any static host).

## Updating

```bash
cd ~/syncubator && git pull
cp raspberry_pi/app.py ~/syncubator_app/app.py
sudo systemctl restart syncubator.service
```

## Troubleshooting

| Symptom | Check |
|---|---|
| A sensor section shows `NOT_CONNECTED` or an alarm says "sensor not responding" | `i2cdetect -y 1` for the address; check power, SDA/SCL and the ADDR pin. The card's restart button re-initialises that driver |
| The app cannot connect | Certificate IP matches the Pi's IP; Nginx running (`systemctl status nginx`); `curl -sk https://<pi-ip>/status` |
| A relay is on at boot | `RELAY_ACTIVE_LOW` does not match the relay board, or the board's input is floating |
| The lid does not move | The L298N channel B ENB pin must be held high |
| Kiosk shows an old page | Redeploy `build/web` and restart Chromium; Nginx sends `no-cache` for the web build |
