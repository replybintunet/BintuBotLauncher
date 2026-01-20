#!/data/data/com.termux/files/usr/bin/python3

from flask import Flask, render_template_string, request
import os
import subprocess
from threading import Thread
import requests
import signal
import atexit

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

# Dictionary to store all running streams
streams = {}

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
* { margin:0; padding:0; box-sizing:border-box; font-family: 'Courier New', monospace; }
body { background: linear-gradient(135deg, #90e0ef, #00b4d8); color:#03045e; display:flex; flex-direction:column; align-items:center; min-height:100vh; padding:20px; }
h1 { font-size:2.5em; color:#0077b6; margin-bottom:30px; text-shadow:1px 1px 2px #fff; }
form { background: rgba(255,255,255,0.9); border-radius:15px; box-shadow:0 8px 20px rgba(0,0,0,0.2); padding:25px 35px; max-width:500px; width:100%; animation: float 6s ease-in-out infinite; }
@keyframes float { 0%,100% { transform: translateY(0px); } 50% { transform: translateY(-10px); } }
label { display:block; margin:15px 0 5px 0; font-weight:bold; }
input[type="text"], input[type="file"] { width:100%; padding:10px; border-radius:8px; border:1px solid #0077b6; }
input[type="checkbox"] { margin-right:8px; }
button { padding:12px 25px; margin:10px 5px; border:none; border-radius:10px; font-weight:bold; cursor:pointer; transition:0.3s; }
button[type="submit"] { background-color:#0077b6; color:#fff; }
button[type="submit"]:hover { background-color:#023e8a; }
.log-computer { position:relative; width:90%; max-width:800px; height:300px; margin-top:40px; background:#03045e; border-radius:20px; box-shadow:0 10px 30px rgba(0,0,0,0.5); overflow:hidden; border:4px solid #0077b6; animation: drift 10s ease-in-out infinite alternate; }
@keyframes drift { 0% { transform: rotate(-1deg); } 50% { transform: rotate(1deg); } 100% { transform: rotate(-1deg); } }
.log-computer::before { content:""; position:absolute; top:10px; left:20px; width:40px; height:15px; background:#00b4d8; border-radius:3px; }
textarea { width:100%; height:100%; background:black; color:#00ff00; padding:15px; border:none; font-family:monospace; font-size:14px; resize:none; overflow-y:auto; }
</style>
</head>
<body>

<h1>Termux YouTube Stream</h1>

<form method="POST" action="/start" enctype="multipart/form-data">
    <label>Upload Video:</label>
    <input type="file" name="video" accept="video/*" required>

    <label>Stream Key:</label>
    <input type="text" name="stream_key" placeholder="Your YouTube Stream Key" required>

    <label>Cloudflare Forwarding URL:</label>
    <input type="text" name="cf_url" placeholder="Optional URL to send to Telegram">

    <label><input type="checkbox" name="mute"> Mute Video</label>
    <label><input type="checkbox" name="loop" checked> Loop Video</label>

    <br>
    <button type="submit">Start Stream</button>
    <button type="submit" formaction="/stop_all">Stop All Streams</button>
</form>

<div class="log-computer">
    <textarea readonly id="log">{{ log }}</textarea>
</div>

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
# Log file
# -----------------------------
LOG_FILE = os.path.join(UPLOAD_FOLDER, 'stream.log')

def log(message):
    with open(LOG_FILE, 'a') as f:
        f.write(message + '\n')
    print(message)

# -----------------------------
# Send Telegram
# -----------------------------
def send_telegram(message):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        requests.post(url, data={"chat_id": CHAT_ID, "text": message})
        log(f"✅ Telegram notified: {message}")
    except Exception as e:
        log(f"❌ Telegram error: {e}")

# -----------------------------
# FFmpeg streaming
# -----------------------------
def start_ffmpeg(stream_id, filepath, stream_key, mute=False, loop=True):
    cmd = ['ffmpeg']
    if loop: cmd += ['-stream_loop', '-1']
    cmd += ['-re', '-i', filepath]
    if mute: cmd += ['-an']
    else: cmd += ['-c:a', 'aac', '-b:a', '128k']
    cmd += ['-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
            '-r', '30', '-g', '60', '-b:v', '2500k',
            '-f', 'flv', f'rtmp://a.rtmp.youtube.com/live2/{stream_key}']

    with open(LOG_FILE, 'a') as f:
        f.write(f"Streaming {os.path.basename(filepath)} with stream_id {stream_id}...\n")

    process = subprocess.Popen(cmd, stderr=subprocess.PIPE, universal_newlines=True)
    streams[stream_id] = process

    for line in process.stderr:
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
    file = request.files['video']
    stream_key = request.form['stream_key']
    cf_url = request.form.get('cf_url')
    mute = 'mute' in request.form
    loop = 'loop' in request.form

    filepath = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(filepath)

    # Unique ID for this stream
    stream_id = file.filename + "_" + stream_key

    # Send Cloudflare URL to Telegram (hidden from front-page)
    if cf_url:
        send_telegram(f"📺 Cloudflare Forwarding URL: {cf_url}")

    # Start streaming in a separate thread
    thread = Thread(target=start_ffmpeg, args=(stream_id, filepath, stream_key, mute, loop))
    thread.start()

    return index()

@app.route('/stop_all', methods=['POST'])
def stop_all():
    log("Stopping all streams...")
    for stream_id, process in streams.items():
        process.terminate()
    streams.clear()
    return index()

@app.route('/log')
def get_log():
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            return f.read()
    return ""

# -----------------------------
# Clean exit
# -----------------------------
def cleanup():
    for process in streams.values():
        process.terminate()

atexit.register(cleanup)
signal.signal(signal.SIGTERM, lambda signum, frame: cleanup())
signal.signal(signal.SIGINT, lambda signum, frame: cleanup())

# -----------------------------
# Run app
# -----------------------------
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)label { display:block; margin:15px 0 5px 0; font-weight:bold; }
input[type="text"], input[type="file"] { width:100%; padding:10px; border-radius:8px; border:1px solid #0077b6; }
input[type="checkbox"] { margin-right:8px; }
button { padding:12px 25px; margin:10px 5px; border:none; border-radius:10px; font-weight:bold; cursor:pointer; transition:0.3s; }
button[type="submit"] { background-color:#0077b6; color:#fff; }
button[type="submit"]:hover { background-color:#023e8a; }
.log-computer { position:relative; width:90%; max-width:800px; height:300px; margin-top:40px; background:#03045e; border-radius:20px; box-shadow:0 10px 30px rgba(0,0,0,0.5); overflow:hidden; border:4px solid #0077b6; animation:drift 10s ease-in-out infinite alternate; }
@keyframes drift { 0%{ transform:rotate(-1deg); } 50%{ transform:rotate(1deg); } 100%{ transform:rotate(-1deg); } }
.log-computer::before { content:""; position:absolute; top:10px; left:20px; width:40px; height:15px; background:#00b4d8; border-radius:3px; }
textarea { width:100%; height:100%; background:black; color:#00ff00; padding:15px; border:none; font-family:monospace; font-size:14px; resize:none; overflow-y:auto; }
.stream-list { margin-top:20px; width:90%; max-width:500px; text-align:left; }
.stream-item { background:#fff; color:#0077b6; padding:10px; border-radius:10px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center; box-shadow:0 5px 10px rgba(0,0,0,0.2); }
.stream-item form { margin:0; }
.stream-item button { background:#d00000; color:#fff; }
</style>
</head>
<body>

<h1>Termux YouTube Stream</h1>

<form method="POST" action="/start" enctype="multipart/form-data">
    <label>Upload Video:</label>
    <input type="file" name="video" accept="video/*" required>

    <label>Stream Key:</label>
    <input type="text" name="stream_key" placeholder="Your YouTube Stream Key" required>

    <input type="hidden" name="cf_url" value="YOUR_CLOUDFLARE_FORWARDING_LINK">

    <label><input type="checkbox" name="mute"> Mute Video</label>
    <label><input type="checkbox" name="loop" checked> Loop Video</label>

    <button type="submit">Start New Stream</button>
</form>

<div class="stream-list">
<h2>Active Streams</h2>
{% for s in streams %}
<div class="stream-item">
    <span>Stream ID: {{ s }}</span>
    <form method="POST" action="/stop/{{ s }}">
        <button type="submit">Stop</button>
    </form>
</div>
{% endfor %}
</div>

<div class="log-computer">
    <textarea readonly id="log">{{ log }}</textarea>
</div>

<script>
function updateLog(){
    fetch('/log').then(r=>r.text()).then(t=>{
        document.getElementById('log').value = t;
        setTimeout(updateLog,1000);
    });
}
updateLog();
</script>

</body>
</html>
"""

# -----------------------------
# Flask Routes
# -----------------------------
@app.route('/')
def index():
    log_content = ''
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            log_content = f.read()
    return render_template_string(HTML, log=log_content, streams=list(streams.keys()))

@app.route('/start', methods=['POST'])
def start():
    file = request.files['video']
    stream_key = request.form['stream_key']
    cf_url = request.form.get('cf_url')
    mute = 'mute' in request.form
    loop = 'loop' in request.form

    filepath = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(filepath)

    if cf_url:
        send_telegram(f"📺 Cloudflare URL: {cf_url}")

    stream_id = str(uuid.uuid4())[:8]
    thread = Thread(target=lambda: streams.update({stream_id: start_ffmpeg(filepath, stream_key, mute, loop)}))
    thread.start()

    return index()

@app.route('/stop/<stream_id>', methods=['POST'])
def stop(stream_id):
    process = streams.get(stream_id)
    if process:
        process.terminate()
        streams.pop(stream_id)
        log(f"Stream {stream_id} stopped by user.")
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
    app.run(host='0.0.0.0', port=5000)    width: 100%; padding: 10px; border-radius: 8px; border: 1px solid #0077b6;
}
input[type="checkbox"] { margin-right: 8px; }

/* Buttons */
button {
    padding: 12px 25px;
    margin: 10px 5px;
    border: none; border-radius: 10px;
    font-weight: bold;
    cursor: pointer;
    transition: 0.3s;
}
button[type="submit"] { background-color: #0077b6; color: #fff; }
button[type="submit"]:hover { background-color: #023e8a; }

/* Log container */
.log-computer {
    position: relative;
    width: 90%;
    max-width: 800px;
    height: 300px;
    margin-top: 40px;
    background: #03045e;
    border-radius: 20px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    overflow: hidden;
    border: 4px solid #0077b6;
    animation: drift 10s ease-in-out infinite alternate;
}

@keyframes drift {
    0% { transform: rotate(-1deg); }
    50% { transform: rotate(1deg); }
    100% { transform: rotate(-1deg); }
}

.log-computer::before {
    content: "";
    position: absolute;
    top: 10px; left: 20px;
    width: 40px; height: 15px;
    background: #00b4d8;
    border-radius: 3px;
}

/* Log textarea */
textarea {
    width: 100%;
    height: 100%;
    background: black;
    color: #00ff00;
    padding: 15px;
    border: none;
    font-family: monospace;
    font-size: 14px;
    resize: none;
    overflow-y: auto;
}
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

    <label><input type="checkbox" name="mute"> Mute Video</label>
    <label><input type="checkbox" name="loop" checked> Loop Video</label>

    <button type="submit">Start Stream</button>
    <button type="submit" formaction="/stop">Stop Stream</button>
</form>

<div class="log-computer">
    <textarea readonly id="log">{{ log }}</textarea>
</div>

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
