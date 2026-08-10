# Replace values with Supabase Dashboard > Connect values.
$SUPABASE_URL = "https://YOUR_PROJECT_REF.supabase.co"
$SUPABASE_KEY = "YOUR_SUPABASE_PUBLISHABLE_KEY"

# Android or connected iOS device
flutter run `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_KEY

# Web on a stable localhost origin for auth redirects
flutter run -d chrome --web-port 3000 `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_KEY
