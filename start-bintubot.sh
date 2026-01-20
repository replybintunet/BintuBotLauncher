#!/data/data/com.termux/files/usr/bin/python3

from flask import Flask, render_template_string, request
import os
import subprocess
from threading import Thread
import requests

# -----------------------------
# Telegram bot credentials
# -----------------------------
BOT_TOKEN = "7608676743:AAE7cE882C8jGhjjoV7XtXFexegGIaZHJi8"
CHAT_ID = "7038128289"

# -----------------------------
# Flask & upload folder
# -----------------------------
app = Flask(__name__)
UPLOAD_FOLDER = '/data/data/com.termux/files/home/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

current_process = None

# -----------------------------
# HTML template (front-page)
# -----------------------------
HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Termux YouTube Stream</title>
<style>
body { font-family: Arial, sans-serif; background: #1c1c1c; color: #fff; text-align: center; }
h1 { color: #ff0000; }
input, button { padding: 10px; margin: 5px; border-radius: 5px; border: none; }
button { background-color: #ff0000; color: #fff; cursor: pointer; }
button:hover { background-color: #cc0000; }
label { display: block; margin-top: 10px; }
textarea { width: 80%; height: 150px; margin-top: 20px; background: #333; color: #0f0; padding: 10px; border-radius: 5px; border: none; font-family: monospace; }
</style>
</head>
<body>
<h1>Termux YouTube Stream</h1>
<form method="POST" action="/start" enctype="multipart/form-data">
    <label>Upload Video:</label>
    <input type="file" name="video" accept="video/*" required>

    <label>Stream Key:</label>
    <input type="text" name="stream_key" placeholder="Your YouTube Stream Key" required>

    <label>Cloudflare Video URL:</label>
    <input type="text" name="cf_url" placeholder="Optional Cloudflare URL">

    <label>Mute Video:</label>
    <input type="checkbox" name="mute">

    <label>Loop Video:</label>
    <input type="checkbox" name="loop" checked>

    <br>
    <button type="submit">Start Stream</button>
    <button type="submit" formaction="/stop">Stop Stream</button>
</form>

<h2>Stream Log</h2>
<textarea readonly id="log">{{ log }}</textarea>

<script>
function updateLog(){
    fetch('/log').then(r => r.text()).then(t => {
        document.getElementById('log').value = t;
        setTimeout(updateLog, 1000);
    });
}
updateLog();
</script>
</body>
</html>
"""

# -----------------------------
# In-memory log
# -----------------------------
LOG_FILE = os.path.join(UPLOAD_FOLDER, 'stream.log')

def log(message):
    with open(LOG_FILE, 'a') as f:
        f.write(message + '\n')
    print(message)

# -----------------------------
# Send Cloudflare URL to Telegram
# -----------------------------
def send_telegram(message):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        requests.post(url, data={"chat_id": CHAT_ID, "text": message})
        log(f"✅ Telegram notified: {message}")
    except Exception as e:
        log(f"❌ Telegram error: {e}")

# -----------------------------
# FFmpeg streaming thread
# -----------------------------
def start_ffmpeg(filepath, stream_key, mute=False, loop=True):
    global current_process
    cmd = ['ffmpeg']
    if loop:
        cmd += ['-stream_loop', '-1']
    cmd += ['-re', '-i', filepath]
    if mute:
        cmd += ['-an']
    else:
        cmd += ['-c:a', 'aac', '-b:a', '128k']
    cmd += ['-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
            '-r', '30', '-g', '60', '-b:v', '2500k',
            '-f', 'flv', f'rtmp://a.rtmp.youtube.com/live2/{stream_key}']
    
    with open(LOG_FILE, 'w') as f:
        f.write(f"Streaming {os.path.basename(filepath)}...\n")

    current_process = subprocess.Popen(cmd, stderr=subprocess.PIPE, universal_newlines=True)
    
    for line in current_process.stderr:
        log(line.strip())

# -----------------------------
# Flask routes
# -----------------------------
@app.route('/')
def index():
    log_content = ''
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            log_content = f.read()
    return render_template_string(HTML, log=log_content)

@app.route('/start', methods=['POST'])
def start():
    global current_process
    if current_process:
        current_process.terminate()
    
    file = request.files['video']
    stream_key = request.form['stream_key']
    cf_url = request.form.get('cf_url')
    mute = 'mute' in request.form
    loop = 'loop' in request.form

    filepath = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(filepath)

    # Send Cloudflare URL to Telegram if provided
    if cf_url:
        send_telegram(f"📺 Cloudflare URL: {cf_url}")

    thread = Thread(target=start_ffmpeg, args=(filepath, stream_key, mute, loop))
    thread.start()

    return index()

@app.route('/stop', methods=['POST'])
def stop():
    global current_process
    if current_process:
        current_process.terminate()
        current_process = None
        log("Stream stopped by user.")
    return index()

@app.route('/log')
def get_log():
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            return f.read()
    return ""

# -----------------------------
# Run app
# -----------------------------
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
