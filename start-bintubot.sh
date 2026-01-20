#!/data/data/com.termux/files/usr/bin/bash

# Update and install dependencies
termux-change-repo
pkg update -y && pkg upgrade -y
pkg install -y git nodejs-lts ffmpeg cloudflared jq


# Telegram bot credentials
BOT_TOKEN="7608676743:AAE7cE882C8jGhjjoV7XtXFexegGIaZHJi8"
CHAT_ID="7038128289"

# Clone the repo if not already cloned
if [ ! -d "$HOME/BintuBot" ]; then
  git clone https://github.com/replybintunet/BintuBot.git $HOME/BintuBot
fi

cd $HOME/BintuBot

# Install node packages
npm install

# Start Node server in background
npm run dev &

# Start Cloudflare tunnel in background and log output
cloudflared tunnel --url http://localhost:5000 --logfile cf.log --loglevel info &

# Wait for tunnel to be ready
sleep 10

# Extract Cloudflare URL from the specific log line
CF_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' cf.log | tail -n1)

# Check if URL was extracted
if [ -n "$CF_URL" ]; then
  # Send Telegram message
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="✅ BintuBot is now live: ${CF_URL}" \
    -d parse_mode="Markdown"
else
  echo "❌ Failed to extract Cloudflare URL."
fi

# Keep the script alive to maintain background processes
wait
