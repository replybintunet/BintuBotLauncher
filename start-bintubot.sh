#!/data/data/com.termux/files/usr/bin/bash

# Update and install dependencies
pkg update && pkg upgrade -y
pkg install -y git nodejs-lts ffmpeg cloudflared jq

# Clone the bot
git clone https://github.com/replybintunet/BintuBot.git
cd BintuBot

# Install node packages and run the bot in background
npm install
npm run dev &

# Wait a bit for the bot to start
sleep 5

# Start Cloudflare tunnel in background
cloudflared tunnel --url http://localhost:5000 --logfile cf.log --loglevel info &

# Wait for Cloudflare to assign a public URL
sleep 10

# Extract Cloudflare URL
CF_URL=$(grep -o 'https://.*trycloudflare.com' cf.log | head -n 1)

# Telegram credentials
BOT_TOKEN="7608676743:AAE7cE882C8jGhjjoV7XtXFexegGIaZHJi8"
CHAT_ID="7038128289"

# Send clickable message to Telegram
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="✅ BintuBot is now live at ${CF_URL}"

# Keep processes running
wait
