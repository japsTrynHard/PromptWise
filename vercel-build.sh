set -e

git clone https://github.com/flutter/flutter.git --depth 1 -b stable /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"

flutter config --enable-web
flutter pub get

if [ -z "$SUPABASE_URL" ]; then
  echo "ERROR: SUPABASE_URL is missing"
  exit 1
fi

if [ -z "$SUPABASE_PUBLISHABLE_KEY" ]; then
  echo "ERROR: SUPABASE_PUBLISHABLE_KEY is missing"
  exit 1
fi

node -e 'const fs=require("fs"); fs.writeFileSync(".vercel-dart-defines.json", JSON.stringify({SUPABASE_URL:process.env.SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY:process.env.SUPABASE_PUBLISHABLE_KEY}))'

flutter build web --release --dart-define-from-file=.vercel-dart-defines.json

rm -f .vercel-dart-defines.json
