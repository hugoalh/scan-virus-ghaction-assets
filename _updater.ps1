[String]$ErrorActionOriginalPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
If ($Env:GITHUB_EVENT_NAME -inotin @('schedule', 'workflow_dispatch')) {
	Write-Host -Object '::error::Invalid event trigger!'
	Exit 1
}
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_csv.psm1') -Scope 'Local'
[AllowEmptyString()][String]$InputFlags = $Env:INPUT_FLAGS
[AllowEmptyString()][String]$InputSchedule = $Env:INPUT_SCHEDULE
[DateTime]$ExecuteTime = Get-Date -AsUTC
[DateTime]$BufferTime = (Get-Date -Date $ExecuteTime -AsUTC).AddMinutes(-30)
[String]$CommitTime = Get-Date -Date $ExecuteTime -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Write-Host -Object "$($PSStyle.Bold)Commit/Execute Time:$($PSStyle.Reset) $CommitTime"
[String[]]$ConditionsAvailable = @('any', "day_$($ExecuteTime.Day)", "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())")
If ($InputFlags.Length -igt 0) {
	ForEach ($Item In ($InputFlags -isplit ';' | ForEach-Object -Process {
		Return $_.Trim()
	} | Where-Object -FilterScript {
		Return ($_.Length -igt 0)
	})) {
		$ConditionsAvailable += "flag_$Item"
	}
}
If ($InputSchedule.Length -gt 0) {
	$ConditionsAvailable += 'schedule'
	[String]$ScheduleHour = $InputSchedule -ireplace '^.+ (?<hour>.+) .+ .+ .+$', '${hour}'
	If ($ScheduleHour -imatch '^\d?\d$') {
		[String]$Condition = "hour_$ScheduleHour"
		$ConditionsAvailable += $Condition
		$ConditionsAvailable += "day_$($ExecuteTime.Day)_$Condition"
		$ConditionsAvailable += "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())_$Condition"
	} Else {
		[string]$Condition = "hour_$($ExecuteTime.Hour)"
		$ConditionsAvailable += $Condition
		$ConditionsAvailable += "day_$($ExecuteTime.Day)_$Condition"
		$ConditionsAvailable += "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())_$Condition"
	}
}
$ConditionsAvailable = ($ConditionsAvailable | Sort-Object -Unique)
Write-Host -Object "$($PSStyle.Bold)Conditions Available ($($ConditionsAvailable.Count)):$($PSStyle.Reset) $($ConditionsAvailable -join ', ')"
ForEach ($AssetDirectory In @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures',
	'yara-rules'
)) {
	Write-Host -Object "At ``$AssetDirectory``."
	[String]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectory
	[String]$AssetIndexFileFullPath = Join-Path -Path $AssetRoot -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Get-Csv -LiteralPath $AssetIndexFileFullPath -Delimiter "`t"
	[String[]]$GitFinishSessions = @()
	For ($AssetIndexNumber = 0; $AssetIndexNumber -ilt $AssetIndex.Count; $AssetIndexNumber++) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexNumber]
		Write-Host -Object "At ``$AssetDirectory/$($AssetIndexItem.Name)``."
		[Boolean]$ShouldUpdate = $False
		ForEach ($Item In ($AssetIndexItem.UpdateCondition -isplit ';' | ForEach-Object -Process {
			Return $_.Trim()
		} | Where-Object -FilterScript {
			Return ($_.Length -igt 0)
		})) {
			If ($Item -iin $ConditionsAvailable) {
				$ShouldUpdate = $True
				Break
			}
		}
		If (
			!$ShouldUpdate -or
			(Get-Date -Date $AssetIndexItem.LastUpdateTime -AsUTC) -igt $BufferTime
		) {
			Write-Host -Object "No need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
			Continue
		}
		Write-Host -Object "Need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
		if ($AssetIndexItem.UpdateMethod -ieq 'Git') {
			[String]$GitName = ($AssetIndexItem.Location -split '[\\\/]')[0]
			[String]$GitSession = "$GitName::$($AssetIndexItem.Source)"
			If ($GitFinishSessions -icontains $GitSession) {
				Write-Host -Object "Skip update ``$AssetDirectory/$($AssetIndexItem.Name)``, repeated Git repository ``$($AssetIndexItem.Source)``."
			} Else {
				Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via Git repository ``$($AssetIndexItem.Source)``."
				[String]$GitWorkingDirectoryRoot = Join-Path -Path $AssetRoot -ChildPath $GitName
				If (Test-Path -LiteralPath $GitWorkingDirectoryRoot) {
					Remove-Item -LiteralPath $GitWorkingDirectoryRoot -Recurse -Force -Confirm:$False
				}
				Set-Location -LiteralPath $AssetRoot
				Try {
					Invoke-Expression -Command "git --no-pager clone --quiet --recurse-submodules `"$($AssetIndexItem.Source)`" `"$GitName`""
					Remove-Item -LiteralPath @(
						(Join-Path -Path $GitWorkingDirectoryRoot -ChildPath '.git'),
						(Join-Path -Path $GitWorkingDirectoryRoot -ChildPath '.github')
					) -Recurse -Force -Confirm:$False
					Get-ChildItem -LiteralPath $GitWorkingDirectoryRoot -Include @(
						'.dockerignore',
						'*.[0-9][0-9][0-9]',
						'*.ai',
						'*.bat',
						'*.bmp',
						'*.cjs',
						'*.db',
						'*.diff',
						'*.dll',
						'*.egg',
						'*.eml',
						'*.exe',
						'*.gif',
						'*.gz',
						'*.html',
						'*.jpeg',
						'*.jpg',
						'*.js',
						'*.lnk',
						'*.log',
						'*.mjs',
						'*.pdf',
						'*.pkg',
						'*.png',
						'*.ps',
						'*.ps1',
						'*.psd',
						'*.psd1',
						'*.psm1',
						'*.py',
						'*.rar',
						'*.rb',
						'*.sh',
						'*.tar.gz',
						'*.tar',
						'*.ts',
						'*.txt',
						'*.xml',
						'*.yaml',
						'*.yml',
						'*.zip',
						'Dockerfile',
						'makefile',
						'Makefile'
					) -Recurse -Force | Remove-Item -Force -Confirm:$False
				} Catch {
					Write-Host -Object "::warning::$_"
				}
				$GitFinishSessions += $GitSession
			}
		} ElseIf ($AssetIndexItem.UpdateMethod -ieq 'WebRequest') {
			Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via web request ``$($AssetIndexItem.Source)``."
			[String]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $AssetIndexItem.Location
			[String]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
			If (!(Test-Path -LiteralPath $OutFileRoot -PathType 'Container')) {
				New-Item -Path $OutFileRoot -ItemType 'Directory' -Confirm:$False
			}
			Start-Sleep -Seconds 1
			Try {
				Invoke-WebRequest -Uri $AssetIndexItem.Source -UseBasicParsing -MaximumRedirection 1 -MaximumRetryCount 3 -RetryIntervalSec 10 -Method 'Get' -OutFile $OutFileFullName
			} Catch {
				Write-Host -Object "::warning::$_"
			}
			Start-Sleep -Seconds 1
		} Else {
			Write-Host -Object "::warning::Cannot update ``$AssetDirectory/$($AssetIndexItem.Name)``, no available update method!"
		}
		$AssetIndex[$AssetIndexNumber].LastUpdateTime = $CommitTime
	}
	Write-Host -Object "At ``$AssetDirectory``."
	Set-Csv -LiteralPath $AssetIndexFileFullPath -InputObject $AssetIndex -Delimiter "`t"
}
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $CommitTime -Confirm:$False -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$CommitTime"
$ErrorActionPreference = $ErrorActionOriginalPreference
