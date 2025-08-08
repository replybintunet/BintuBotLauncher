#!/data/data/com.termux/files/usr/bin/bash

# Update and install dependencies
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

# Colors
RESET="\e[0m"
WHITE_ON_BLUE="\e[1;97m\e[48;5;39m"  # Sky blue background (color 39), white text

# Simulate button (icon + label)
function print_button() {
  echo -e "${WHITE_ON_BLUE}  ≡  Open Link  ${RESET}"
  echo -e "${WHITE_ON_BLUE}  📋  Copy Link  ${RESET}"
}

# Extracted Cloudflare URL
if [ -n "$CF_URL" ]; then
  # Send Telegram notification
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="✅ *BintuBot is now live:* [Click to Open](${CF_URL})" \
    -d parse_mode="Markdown"

  # Display button-style output
  echo -e "\n\e[1;97m\e[48;5;39m=========== BintuBot Online ===========${RESET}"
  echo -e "${WHITE_ON_BLUE} ✅ Live at: $CF_URL ${RESET}"
  print_button
  echo -e "\e[1;97m\e[48;5;39m=======================================${RESET}\n"

  # Optional: copy to clipboard and open link
  echo "$CF_URL" | termux-clipboard-set
  xdg-open "$CF_URL" >/dev/null 2>&1 &
else
  echo -e "\e[1;97m\e[41m❌ Failed to extract Cloudflare URL.\e[0m"
fi

# Keep the script alive to maintain background processes
wait
