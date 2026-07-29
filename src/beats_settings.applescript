set repoRoot to "__REPO_ROOT__"
set helperScript to repoRoot & "/scripts/beats_config.py"

on readProfileNames(helperScript)
  set profileData to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " list-profiles"
  if profileData is "" then return {}
  set profileNames to {}
  repeat with profileLine in paragraphs of profileData
    set AppleScript's text item delimiters to tab
    set profileParts to text items of profileLine
    set AppleScript's text item delimiters to ""
    if (count of profileParts) is greater than or equal to 2 then set end of profileNames to item 1 of profileParts
  end repeat
  return profileNames
end readProfileNames

on readSourceNames(helperScript, kindFilter)
  set sourceCommand to quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " list-sources"
  if kindFilter is not "" then
    set sourceCommand to sourceCommand & " --kind " & quoted form of kindFilter
  end if
  set sourceData to do shell script sourceCommand
  if sourceData is "" then return {}
  set sourceNames to {}
  repeat with sourceLine in paragraphs of sourceData
    set AppleScript's text item delimiters to tab
    set sourceParts to text items of sourceLine
    set AppleScript's text item delimiters to ""
    if (count of sourceParts) is greater than or equal to 2 then set end of sourceNames to item 1 of sourceParts
  end repeat
  return sourceNames
end readSourceNames

on readWifiRuleSSIDs(helperScript)
  set wifiData to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " list-wifi-rules"
  if wifiData is "" then return {}
  set wifiSSIDs to {}
  repeat with wifiLine in paragraphs of wifiData
    set AppleScript's text item delimiters to tab
    set wifiParts to text items of wifiLine
    set AppleScript's text item delimiters to ""
    if (count of wifiParts) is greater than or equal to 1 then set end of wifiSSIDs to item 1 of wifiParts
  end repeat
  return wifiSSIDs
end readWifiRuleSSIDs

on readTimeRuleLabels(helperScript)
  set timeData to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " list-time-rules"
  if timeData is "" then return {}
  set ruleLabels to {}
  repeat with timeLine in paragraphs of timeData
    set AppleScript's text item delimiters to tab
    set timeParts to text items of timeLine
    set AppleScript's text item delimiters to ""
    if (count of timeParts) is greater than or equal to 4 then
      set ruleIndex to item 1 of timeParts
      set startTime to item 2 of timeParts
      set endTime to item 3 of timeParts
      set profileName to item 4 of timeParts
      set end of ruleLabels to ruleIndex & ": " & startTime & "-" & endTime & " -> " & profileName
    end if
  end repeat
  return ruleLabels
end readTimeRuleLabels

try
  set actionChoice to choose from list {"View Settings", "Set Hardware Target", "Set Boom 3D App Path", "Set Status File Path", "Set Default Profile", "View Profiles", "Add or Update Profile", "Remove Profile", "View Auto-Profile Rules", "Set Wi-Fi Rule", "Remove Wi-Fi Rule", "Add Time Rule", "Remove Time Rule", "Set Fallback Profile"} with title "Beats_Settings" with prompt "Choose action:" default items {"View Settings"} without multiple selections allowed
  if actionChoice is false then return

  set selectedAction to item 1 of actionChoice

  if selectedAction is "View Settings" then
    set settingsSummary to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " view-settings"
    display dialog settingsSummary buttons {"OK"} default button "OK"

  else if selectedAction is "Set Hardware Target" then
    set currentHeadphonesName to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " get-setting default_headphones_name"
    set currentHeadphonesMac to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " get-setting default_headphones_mac"
    set headphonesName to text returned of (display dialog "Headphones name:" default answer currentHeadphonesName buttons {"Cancel", "Next"} default button "Next")
    set headphonesMac to text returned of (display dialog "Headphones MAC address:" default answer currentHeadphonesMac buttons {"Cancel", "Save"} default button "Save")
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " update-setting default_headphones_name " & quoted form of headphonesName
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " update-setting default_headphones_mac " & quoted form of headphonesMac
    display notification "Hardware target updated" with title "Beats_Settings"

  else if selectedAction is "Set Boom 3D App Path" then
    set currentBoomPath to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " get-setting boom_3d_app"
    set boomPath to text returned of (display dialog "Boom 3D app path:" default answer currentBoomPath buttons {"Cancel", "Save"} default button "Save")
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " update-setting boom_3d_app " & quoted form of boomPath
    display notification "Boom 3D path updated" with title "Beats_Settings"

  else if selectedAction is "Set Status File Path" then
    set currentStatusPath to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " get-setting status_file_path"
    set statusPath to text returned of (display dialog "Status file path:" default answer currentStatusPath buttons {"Cancel", "Save"} default button "Save")
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " update-setting status_file_path " & quoted form of statusPath
    display notification "Status file path updated" with title "Beats_Settings"

  else if selectedAction is "Set Default Profile" then
    set profileNames to readProfileNames(helperScript)
    if profileNames is {} then
      display dialog "No profiles configured." buttons {"OK"} default button "OK"
      return
    end if
    set currentDefaultProfile to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " get-default-profile"
    set selectedProfileChoice to choose from list profileNames with title "Beats_Settings" with prompt "Choose default profile:" default items {currentDefaultProfile} without multiple selections allowed
    if selectedProfileChoice is false then return
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " set-default-profile " & quoted form of (item 1 of selectedProfileChoice)
    display notification "Default profile updated" with title "Beats_Settings"

  else if selectedAction is "View Profiles" then
    set profileSummary to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " view-profiles"
    display dialog profileSummary buttons {"OK"} default button "OK"

  else if selectedAction is "Add or Update Profile" then
    set profileName to text returned of (display dialog "Profile name:" default answer "" buttons {"Cancel", "Next"} default button "Next")
    if profileName is "" then return

    set sourceTypeChoice to choose from list {"Apple Music Playlist", "URL", "Headphones Only"} with title "Beats_Settings" with prompt "Choose profile source type:" default items {"Apple Music Playlist"} without multiple selections allowed
    if sourceTypeChoice is false then return
    set selectedSourceType to item 1 of sourceTypeChoice

    if selectedSourceType is "Apple Music Playlist" then
      set sourceNames to readSourceNames(helperScript, "apple_music")
      if sourceNames is {} then
        display dialog "No Apple Music playlist sources configured." buttons {"OK"} default button "OK"
        return
      end if
      set selectedSourceChoice to choose from list sourceNames with title "Beats_Settings" with prompt "Choose default Apple Music source:" default items {"Focus Noise"} without multiple selections allowed
      if selectedSourceChoice is false then return
      set profileSource to item 1 of selectedSourceChoice
      set profileSourceType to "apple_music"
    else if selectedSourceType is "URL" then
      set sourceNames to readSourceNames(helperScript, "url")
      if sourceNames is {} then
        display dialog "No URL sources configured." buttons {"OK"} default button "OK"
        return
      end if
      set selectedSourceChoice to choose from list sourceNames with title "Beats_Settings" with prompt "Choose default URL source:" without multiple selections allowed
      if selectedSourceChoice is false then return
      set profileSource to item 1 of selectedSourceChoice
      set profileSourceType to "url"
    else
      set profileSource to "Headphones Only"
      set profileSourceType to "none"
    end if

    set profileNote to text returned of (display dialog "Boom note (reminder only; does not change Boom presets):" default answer "" buttons {"Cancel", "Next"} default button "Next")
    set headphonesName to text returned of (display dialog "Headphones name override (blank keeps default):" default answer "" buttons {"Cancel", "Next"} default button "Next")
    set headphonesMac to text returned of (display dialog "Headphones MAC override (blank keeps default):" default answer "" buttons {"Cancel", "Save"} default button "Save")

    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " upsert-profile " & quoted form of profileName & " " & quoted form of profileSource & " " & quoted form of profileSourceType & " " & quoted form of profileNote & " " & quoted form of headphonesName & " " & quoted form of headphonesMac
    display notification profileName & " saved" with title "Beats_Settings"

  else if selectedAction is "Remove Profile" then
    set profileNames to readProfileNames(helperScript)
    if profileNames is {} then
      display dialog "No profiles configured." buttons {"OK"} default button "OK"
      return
    end if
    set selectedProfileChoice to choose from list profileNames with title "Beats_Settings" with prompt "Remove profile:" without multiple selections allowed
    if selectedProfileChoice is false then return
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " remove-profile " & quoted form of (item 1 of selectedProfileChoice)
    display notification (item 1 of selectedProfileChoice) & " removed" with title "Beats_Settings"

  else if selectedAction is "View Auto-Profile Rules" then
    set rulesSummary to do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " view-profile-rules"
    display dialog rulesSummary buttons {"OK"} default button "OK"

  else if selectedAction is "Set Wi-Fi Rule" then
    set profileNames to readProfileNames(helperScript)
    if profileNames is {} then
      display dialog "No profiles configured." buttons {"OK"} default button "OK"
      return
    end if
    set wifiName to text returned of (display dialog "Wi-Fi SSID:" default answer "" buttons {"Cancel", "Next"} default button "Next")
    if wifiName is "" then return
    set selectedProfileChoice to choose from list profileNames with title "Beats_Settings" with prompt "Choose profile for this Wi-Fi:" without multiple selections allowed
    if selectedProfileChoice is false then return
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " set-wifi-rule " & quoted form of wifiName & " " & quoted form of (item 1 of selectedProfileChoice)
    display notification "Wi-Fi rule saved" with title "Beats_Settings"

  else if selectedAction is "Remove Wi-Fi Rule" then
    set wifiLabels to readWifiRuleSSIDs(helperScript)
    if wifiLabels is {} then
      display dialog "No Wi-Fi rules configured." buttons {"OK"} default button "OK"
      return
    end if
    set wifiChoice to choose from list wifiLabels with title "Beats_Settings" with prompt "Remove Wi-Fi rule:" without multiple selections allowed
    if wifiChoice is false then return
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " remove-wifi-rule " & quoted form of (item 1 of wifiChoice)
    display notification "Wi-Fi rule removed" with title "Beats_Settings"

  else if selectedAction is "Add Time Rule" then
    set profileNames to readProfileNames(helperScript)
    if profileNames is {} then
      display dialog "No profiles configured." buttons {"OK"} default button "OK"
      return
    end if
    set startTime to text returned of (display dialog "Start time (HH:MM):" default answer "09:00" buttons {"Cancel", "Next"} default button "Next")
    set endTime to text returned of (display dialog "End time (HH:MM):" default answer "12:00" buttons {"Cancel", "Next"} default button "Next")
    set selectedProfileChoice to choose from list profileNames with title "Beats_Settings" with prompt "Choose profile for this time range:" without multiple selections allowed
    if selectedProfileChoice is false then return
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " add-time-rule " & quoted form of startTime & " " & quoted form of endTime & " " & quoted form of (item 1 of selectedProfileChoice)
    display notification "Time rule saved" with title "Beats_Settings"

  else if selectedAction is "Remove Time Rule" then
    set timeRuleLabels to readTimeRuleLabels(helperScript)
    if timeRuleLabels is {} then
      display dialog "No time rules configured." buttons {"OK"} default button "OK"
      return
    end if
    set timeRuleChoice to choose from list timeRuleLabels with title "Beats_Settings" with prompt "Remove time rule:" without multiple selections allowed
    if timeRuleChoice is false then return
    set selectedLabel to item 1 of timeRuleChoice
    set AppleScript's text item delimiters to ":"
    set labelParts to text items of selectedLabel
    set AppleScript's text item delimiters to ""
    set ruleIndex to (item 1 of labelParts as integer) - 1
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " remove-time-rule " & quoted form of (ruleIndex as text)
    display notification "Time rule removed" with title "Beats_Settings"

  else if selectedAction is "Set Fallback Profile" then
    set profileNames to readProfileNames(helperScript)
    if profileNames is {} then
      display dialog "No profiles configured." buttons {"OK"} default button "OK"
      return
    end if
    set fallbackChoices to profileNames
    set end of fallbackChoices to "None"
    set fallbackChoice to choose from list fallbackChoices with title "Beats_Settings" with prompt "Choose fallback profile:" without multiple selections allowed
    if fallbackChoice is false then return
    set fallbackProfile to item 1 of fallbackChoice
    if fallbackProfile is "None" then set fallbackProfile to ""
    do shell script quoted form of "__BEATS_PYTHON__" & " " & quoted form of helperScript & " set-fallback-profile " & quoted form of fallbackProfile
    display notification "Fallback profile updated" with title "Beats_Settings"
  end if
on error errMsg number errNum
  set AppleScript's text item delimiters to ""
  if errNum is -128 then return
  display dialog "Beats_Settings failed:" & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
end try
