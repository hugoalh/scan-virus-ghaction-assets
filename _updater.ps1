#Requires -PSEdition Core
#Requires -Version 7.2
$Script:ErrorActionPreference = 'Stop'
Import-Module -Name 'hugoalh.GitHubActionsToolkit' -Scope 'Local'
Write-Host -Object 'Initialize.'
[String[]]$GitIgnores = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_updater_gitignore.txt') -Encoding 'UTF8NoBOM' |
	Where-Object -FilterScript { $_.Length -igt 0 }
[Hashtable]$ImportCsvParameters_Tsv = @{
	Delimiter = "`t"
	Encoding = 'UTF8NoBOM'
}
[String]$MetadataFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'metadata.json'
[DateTime]$TimeInvoke = Get-Date -AsUTC
[DateTime]$TimeBuffer = (Get-Date -Date $TimeInvoke -AsUTC).AddMinutes(-30)
[String]$TimeCommit = Get-Date -Date $TimeInvoke -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Write-Host -Object "$($PSStyle.Bold)Commit/Invoke Time: $($PSStyle.Reset)$TimeCommit"
Write-Host -Object 'Config Git.'
git --no-pager config 'user.name' 'github-actions'
git --no-pager config 'user.email' 'github-actions@github.com'
Write-Host -Object 'Import updater event trigger.'
[AllowEmptyString()][String]$InputEvent = ($Env:GITHUB_EVENT_NAME ?? '') -ireplace '_', '-'
If ($InputEvent -inotin @('schedule', 'workflow-dispatch')) {
	Write-GitHubActionsFail -Message "``$InputEvent`` is not a valid updater event trigger!"
	Exit 1
}
[String[]]$ConditionsAvailable = @(
	"event:$InputEvent"
)
Write-Host -Object 'Import updater flags.'
[AllowEmptyString()][String]$InputFlags = $Env:INPUT_FLAGS
If ($InputFlags.Length -igt 0) {
	ForEach ($Item In (
		[String[]]($InputFlags -isplit ';') |
			ForEach-Object -Process { $_.Trim() } |
			Where-Object -FilterScript { $_.Length -igt 0 }
	)) {
		$ConditionsAvailable += "flag:$Item"
	}
}
Write-Host -Object 'Import updater scheduler.'
[AllowEmptyString()][String]$InputSchedule = $Env:INPUT_SCHEDULE
If ($InputSchedule.Length -igt 0) {
	[String]$ScheduleHour = $InputSchedule -ireplace '^.+ (?<Hour>.+) .+ .+ .+$', '${Hour}'
	$ConditionsAvailable += "timetoken:$(($ScheduleHour -imatch '^(?:1?\d|2[0-3])$') ? $ScheduleHour : $TimeInvoke.Hour) $($TimeInvoke.Day) $($TimeInvoke.Month) $($TimeInvoke.DayOfWeek.GetHashCode())"
}
$ConditionsAvailable = $ConditionsAvailable |
	Sort-Object -Unique
Write-Host -Object "$($PSStyle.Bold)Conditions Available ($($ConditionsAvailable.Count)): $($PSStyle.BoldOff)$(
	$ConditionsAvailable |
		Join-String -Separator ', '
)"
Write-Host -Object 'Begin update assets.'
ForEach ($AssetDirectory In @('clamav-signatures-ignore-presets', 'clamav-unofficial-signatures', 'yara-rules')) {
	Write-Host -Object "At ``$AssetDirectory``."
	Write-Host -Object 'Read asset index.'
	[String]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectory
	[String]$AssetIndexFileFullPath = Join-Path -Path $AssetRoot -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Import-Csv -LiteralPath $AssetIndexFileFullPath @ImportCsvParameters_Tsv
	[String[]]$GitFinishSessions = @()
	For ($AssetIndexNumber = 0; $AssetIndexNumber -ilt $AssetIndex.Count; $AssetIndexNumber++) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexNumber]
		Write-Host -Object "At ``$AssetDirectory/$($AssetIndexItem.Name)``."
		If (
			($ConditionsAvailable -imatch $AssetIndexItem.UpdateCondition).Count -ieq 0 -or
			(Get-Date -Date $AssetIndexItem.LastUpdateTime -AsUTC) -igt $TimeBuffer
		) {
			Write-Host -Object "No need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
			Continue
		}
		Write-Host -Object "Need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
		If ($AssetIndexItem.UpdateMethod -ieq 'Git') {
			[String]$GitName = $AssetIndexItem.Location -isplit '[\\\/]' |
				Select-Object -First 1
			[String]$GitSession = "$GitName::$($AssetIndexItem.Source)"
			If ($GitFinishSessions -icontains $GitSession) {
				Write-Host -Object "Skip update ``$AssetDirectory/$($AssetIndexItem.Name)``, repeated Git repository ``$($AssetIndexItem.Source)``."
			}
			Else {
				Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via Git repository ``$($AssetIndexItem.Source)``."
				[String]$GitWorkingDirectoryRoot = Join-Path -Path $AssetRoot -ChildPath $GitName
				If (Test-Path -LiteralPath $GitWorkingDirectoryRoot) {
					Remove-Item -LiteralPath $GitWorkingDirectoryRoot -Recurse -Force -Confirm:$False
				}
				Set-Location -LiteralPath $AssetRoot
				Try {
					Invoke-Expression -Command "git --no-pager clone --quiet --recurse-submodules `"$($AssetIndexItem.Source)`" `"$GitName`""
					Get-ChildItem -LiteralPath $GitWorkingDirectoryRoot -Include $GitIgnores -Recurse -Force |
						Remove-Item -Recurse -Force -Confirm:$False
				}
				Catch {
					Write-GitHubActionsWarning -Message $_
				}
				Set-Location -LiteralPath $PSScriptRoot
				$GitFinishSessions += $GitSession
			}
		}
		ElseIf ($AssetIndexItem.UpdateMethod -ieq 'WebRequest') {
			Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via web request ``$($AssetIndexItem.Source)``."
			[String]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $AssetIndexItem.Location
			[String]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
			If (!(Test-Path -LiteralPath $OutFileRoot -PathType 'Container')) {
				New-Item -Path $OutFileRoot -ItemType 'Directory' -Confirm:$False |
					Out-Null
			}
			Try {
				Invoke-WebRequest -Uri $AssetIndexItem.Source -UseBasicParsing -MaximumRedirection 1 -MaximumRetryCount 3 -RetryIntervalSec 10 -Method 'Get' -OutFile $OutFileFullName
			}
			Catch {
				Write-GitHubActionsWarning -Message $_
			}
		}
		Else {
			Write-GitHubActionsWarning -Message "Unable to update ``$AssetDirectory/$($AssetIndexItem.Name)``, no available update method!"
		}
		$AssetIndex[$AssetIndexNumber].LastUpdateTime = $TimeCommit
	}
	Write-Host -Object "At ``$AssetDirectory``."
	Write-Host -Object 'Update asset index.'
	$AssetIndex |
		Export-Csv -LiteralPath $AssetIndexFileFullPath @ImportCsvParameters_Tsv -NoTypeInformation -UseQuotes 'AsNeeded' -Confirm:$False
}
Write-Host -Object 'Write metadata.'
[PSCustomObject]$Metadata = Get-Content -LiteralPath $MetadataFilePath -Raw -Encoding 'UTF8NoBOM' |
	ConvertFrom-Json -Depth 100
$Metadata.Timestamp = $TimeCommit
Set-Content -LiteralPath $MetadataFilePath -Value (
	$Metadata |
		ConvertTo-Json -Depth 100 -Compress
) -Confirm:$False -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object 'Push Git commit.'
git --no-pager add --all
Invoke-Expression -Command "git --no-pager commit --message=`"Update assets on $TimeCommit`""
git --no-pager push
