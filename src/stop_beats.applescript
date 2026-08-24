try
  set repoRoot to "__REPO_ROOT__"
  set stopScript to repoRoot & "/scripts/beats-stop.sh"
  do shell script quoted form of stopScript & " 2>&1"
on error errMsg number errNum
  if errNum is -128 then return
  display dialog "Stop_Beats failed:" & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
end try
