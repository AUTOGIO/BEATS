try
  set repoRoot to "__REPO_ROOT__"
  set helperScript to repoRoot & "/scripts/beats_config.py"
  set runnerScript to repoRoot & "/scripts/beats-headphones.sh"
  set statusFile to do shell script "/usr/bin/python3 " & quoted form of helperScript & " get-setting status_file_path"

  set defaultProfile to do shell script "/usr/bin/python3 " & quoted form of helperScript & " get-default-profile"
  set profileData to do shell script "/usr/bin/python3 " & quoted form of helperScript & " list-profiles"

  set profileLines to paragraphs of profileData
  set profileOptions to {}
  repeat with profileLine in profileLines
    set AppleScript's text item delimiters to tab
    set profileParts to text items of profileLine
    set AppleScript's text item delimiters to ""
    if (count of profileParts) is greater than or equal to 2 then
      set end of profileOptions to item 1 of profileParts
    end if
  end repeat
  set end of profileOptions to "Manual Session"

  if defaultProfile is "" then set defaultProfile to "Manual Session"
  set selectedProfileChoice to choose from list profileOptions with title "Focus_Beats" with prompt "Choose session profile:" default items {defaultProfile} without multiple selections allowed
  if selectedProfileChoice is false then return

  set selectedProfile to item 1 of selectedProfileChoice
  set profileDefaultSource to "Focus Noise"
  set profileDefaultSourceType to "apple_music"
  set profileNote to ""

  if selectedProfile is not "Manual Session" then
    repeat with profileLine in profileLines
      set AppleScript's text item delimiters to tab
      set profileParts to text items of profileLine
      set AppleScript's text item delimiters to ""
      if (count of profileParts) is greater than or equal to 4 then
        if item 1 of profileParts is selectedProfile then
          set profileDefaultSource to item 2 of profileParts
          set profileDefaultSourceType to item 3 of profileParts
          set profileNote to item 4 of profileParts
          exit repeat
        end if
      end if
    end repeat
  end if

  set sourceData to do shell script "/usr/bin/python3 " & quoted form of helperScript & " list-sources"
  set sourceLines to paragraphs of sourceData
  set sourceOptions to {}
  repeat with sourceLine in sourceLines
    set AppleScript's text item delimiters to tab
    set sourceParts to text items of sourceLine
    set AppleScript's text item delimiters to ""
    if (count of sourceParts) is greater than or equal to 2 then
      set end of sourceOptions to item 1 of sourceParts
    end if
  end repeat

  set end of sourceOptions to "Custom URL"
  set end of sourceOptions to "Headphones Only"

  if profileDefaultSourceType is "none" then
    set profileDefaultSource to "Headphones Only"
  else if profileDefaultSource is "" then
    set profileDefaultSource to "Focus Noise"
  end if

  if profileNote is "" then
    set sourcePrompt to "Choose music source:"
  else
    set sourcePrompt to "Choose music source:" & return & return & "Boom note: " & profileNote
  end if

  if selectedProfile is not "Manual Session" then
    if profileDefaultSourceType is "apple_music" then
      set sourcePrompt to sourcePrompt & return & "Profile source type: Apple Music"
    else if profileDefaultSourceType is "url" then
      set sourcePrompt to sourcePrompt & return & "Profile source type: URL"
    else if profileDefaultSourceType is "none" then
      set sourcePrompt to sourcePrompt & return & "Profile source type: Headphones Only"
    end if
  end if

  set selectedSourceChoice to choose from list sourceOptions with title "Focus_Beats" with prompt sourcePrompt default items {profileDefaultSource} without multiple selections allowed
  if selectedSourceChoice is false then return

  set selectedSource to item 1 of selectedSourceChoice
  if selectedSource is "Custom URL" then
    set selectedSource to text returned of (display dialog "Paste music URL:" default answer "" buttons {"Cancel", "Play"} default button "Play")
    if selectedSource is "" then return
  end if

  set shellCommand to quoted form of runnerScript & " --status-file " & quoted form of statusFile & " --music-source " & quoted form of selectedSource
  if selectedProfile is not "Manual Session" then
    set shellCommand to shellCommand & " --profile " & quoted form of selectedProfile
  end if

  try
    do shell script shellCommand & " 2>&1"
  on error errMsg number errNum
    set summaryText to do shell script "/usr/bin/python3 - " & quoted form of statusFile & " <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print('Run failed before status summary was generated.')
    raise SystemExit(0)

data = json.loads(path.read_text())
lines = []
profile_name = data.get('profile', {}).get('name') or 'Manual Session'
music_label = data.get('music', {}).get('label') or 'Headphones Only'
lines.append(f'Profile: {profile_name}')
lines.append(f'Music: {music_label}')
for step in data.get('steps', []):
    lines.append(f\"{step['label']}: {step['status']} - {step['detail']}\")
print('\\n'.join(lines))
PY"
    if errNum is -128 then return
    display dialog "Focus_Beats summary:" & return & return & summaryText & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
    return
  end try

  set summaryText to do shell script "/usr/bin/python3 - " & quoted form of statusFile & " <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print('No status summary generated.')
    raise SystemExit(0)

data = json.loads(path.read_text())
lines = []
profile_name = data.get('profile', {}).get('name') or 'Manual Session'
music_label = data.get('music', {}).get('label') or 'Headphones Only'
lines.append(f'Profile: {profile_name}')
lines.append(f'Music: {music_label}')
for step in data.get('steps', []):
    lines.append(f\"{step['label']}: {step['status']} - {step['detail']}\")
print('\\n'.join(lines))
PY"
  display dialog summaryText buttons {"OK"} default button "OK" with icon note
on error errMsg number errNum
  set AppleScript's text item delimiters to ""
  if errNum is -128 then return
  display dialog "Focus_Beats failed:" & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
end try
