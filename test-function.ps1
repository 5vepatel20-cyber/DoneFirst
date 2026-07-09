# Tests the deployed verify-proof Edge Function.
# Run from PowerShell: powershell -ExecutionPolicy Bypass -File .\test-function.ps1

$ErrorActionPreference = 'Stop'
$SUPABASE_URL = 'https://wxjtksxugsirpowptpmz.supabase.co'
$FUNCTION_URL = $SUPABASE_URL + '/functions/v1/verify-proof'
$ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind4anRrc3h1Z3NpcnBvd3B0cG16Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzMzMzMTgsImV4cCI6MjA5ODkwOTMxOH0.Ng9onu4901Q1yY0YnrM1XLyo5yOBoQbUariFqG-M3go'

Write-Host '=== Test verify-proof Edge Function ===' -ForegroundColor Cyan
Write-Host ''

# ---------- Test 1: no auth (should return 401) ----------
Write-Host 'Test 1: Calling without auth (should return 401)' -ForegroundColor Yellow
try {
  $headers = @{ 'Content-Type' = 'application/json' }
  $resp = Invoke-WebRequest -Uri $FUNCTION_URL -Method Post -Body '{"imageUrl":"x"}' -Headers $headers -UseBasicParsing -StatusCodeVariable statusCode
  Write-Host ('  Status: ' + $statusCode) -ForegroundColor Green
  Write-Host ('  Body: ' + $resp.Content) -ForegroundColor Green
} catch {
  $msg = $_.Exception.Message
  Write-Host ('  Response (no auth): ' + $msg) -ForegroundColor Green
}
Write-Host ''

# ---------- Prompt for credentials ----------
$email = Read-Host 'Test account email'
$securePass = Read-Host 'Test account password' -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
Write-Host ''

# ---------- Test 2: sign in to get a real token ----------
Write-Host ('Test 2: Signing in as ' + $email + '...') -ForegroundColor Yellow
$loginBody = @{ email = $email; password = $password } | ConvertTo-Json
try {
  $loginResp = Invoke-RestMethod -Uri ($SUPABASE_URL + '/auth/v1/token?grant_type=password') -Method Post -Headers @{ 'apikey' = $ANON_KEY; 'Content-Type' = 'application/json' } -Body $loginBody
  $token = $loginResp.access_token
  Write-Host ('  Signed in. Token starts with: ' + $token.Substring(0, 20) + '...') -ForegroundColor Green
} catch {
  Write-Host ('  FAILED to sign in: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
Write-Host ''

# ---------- Test 3: call the function with the real token ----------
Write-Host 'Test 3: Calling verify-proof with auth...' -ForegroundColor Yellow
$body = '{"imageUrl":"https://wxjtksxugsirpowptpmz.supabase.co/storage/v1/object/sign/proof-photos/test.jpg"}'
try {
  $r = Invoke-RestMethod -Uri $FUNCTION_URL -Method Post -Headers @{ 'Authorization' = ('Bearer ' + $token); 'Content-Type' = 'application/json' } -Body $body
  Write-Host ('  Response: ' + ($r | ConvertTo-Json -Compress)) -ForegroundColor Green
  Write-Host ''
  if ($r.reason -like '*Missing API key*') {
    Write-Host '  WARNING: MISTRAL_API_KEY env var is not set. Go back to Step 9.' -ForegroundColor Red
  } elseif ($r.reason -like '*Unauthorized*') {
    Write-Host '  WARNING: function rejected the token. Check the JWT format.' -ForegroundColor Red
  } elseif ($r.reason -like '*must be a Supabase Storage URL*') {
    Write-Host '  WARNING: URL validation rejected the URL. Check the prefix.' -ForegroundColor Red
  } elseif ($r.reason -like '*Daily verification limit reached*') {
    Write-Host '  SUCCESS: function is working -- you just hit the daily cap.' -ForegroundColor Green
  } else {
    Write-Host '  SUCCESS: function responded. Mistral may or may not have identified the test image.' -ForegroundColor Green
  }
} catch {
  Write-Host ('  FAILED: ' + $_.Exception.Message) -ForegroundColor Red
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $body = $reader.ReadToEnd()
    Write-Host ('  Response body: ' + $body) -ForegroundColor Yellow
  }
}
