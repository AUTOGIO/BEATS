set repoRoot to "__REPO_ROOT__"
set helperScript to repoRoot & "/scripts/beats_config.py"

on readSources()
  set sourceData to do shell script "/usr/bin/python3 " & quoted form of helperScript & " list-sources"
  if sourceData is "" then return {}
  return paragraphs of sourceData
end readSources

try
  set actionChoice to choose from list {"Add Source", "Remove Source", "View Sources"} with title "Beats_Source" with prompt "Choose action:" default items {"Add Source"} without multiple selections allowed
  if actionChoice is false then return

  set selectedAction to item 1 of actionChoice

  if selectedAction is "Add Source" then
    set sourceLabel to text returned of (display dialog "Source name:" default answer "" buttons {"Cancel", "Next"} default button "Next")
    if sourceLabel is "" then return

    set sourceValue to text returned of (display dialog "Playlist name or music URL:" default answer "" buttons {"Cancel", "Save"} default button "Save")
    if sourceValue is "" then return

    do shell script "/usr/bin/python3 " & quoted form of helperScript & " upsert-source " & quoted form of sourceLabel & " " & quoted form of sourceValue
    display notification sourceLabel & " saved" with title "Beats_Source"

  else if selectedAction is "Remove Source" then
    set sourceLines to readSources()
    if sourceLines is {} then
      display dialog "No music sources to remove." buttons {"OK"} default button "OK"
      return
    end if

    set sourceLabels to {}
    repeat with sourceLine in sourceLines
      set AppleScript's text item delimiters to tab
      set sourceParts to text items of sourceLine
      set AppleScript's text item delimiters to ""
      if (count of sourceParts) is greater than or equal to 2 then set end of sourceLabels to item 1 of sourceParts
    end repeat

    set removeChoice to choose from list sourceLabels with title "Beats_Source" with prompt "Remove source:" without multiple selections allowed
    if removeChoice is false then return

    set removeLabel to item 1 of removeChoice
    do shell script "/usr/bin/python3 " & quoted form of helperScript & " remove-source " & quoted form of removeLabel
    display notification removeLabel & " removed" with title "Beats_Source"

  else if selectedAction is "View Sources" then
    set sourceLines to readSources()
    if sourceLines is {} then
      set sourceSummary to "No music sources configured."
    else
      set sourceSummary to ""
      repeat with sourceLine in sourceLines
        set AppleScript's text item delimiters to tab
        set sourceParts to text items of sourceLine
        set AppleScript's text item delimiters to ""
        if (count of sourceParts) is greater than or equal to 2 then
          set sourceSummary to sourceSummary & item 1 of sourceParts & " -> " & item 2 of sourceParts & return
        end if
      end repeat
    end if
    display dialog sourceSummary buttons {"OK"} default button "OK"
  end if
on error errMsg number errNum
  set AppleScript's text item delimiters to ""
  if errNum is -128 then return
  display dialog "Beats_Source failed:" & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
end try
