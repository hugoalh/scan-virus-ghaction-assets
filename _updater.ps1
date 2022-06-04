[string]$ErrorActionOriginalPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_EVENT_NAME -inotin @('schedule', 'workflow_dispatch')) {
	Write-Host -Object '::error::Invalid event trigger!'
	exit 1
}
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_csv.psm1') -Scope 'Local'
[AllowEmptyString()][string]$InputFlags = $env:INPUT_FLAGS
[AllowEmptyString()][string]$InputSchedule = $env:INPUT_SCHEDULE
[datetime]$ExecuteTime = Get-Date -AsUTC
[datetime]$BufferTime = (Get-Date -Date $ExecuteTime -AsUTC).AddMinutes(-30)
[string]$CommitTime = Get-Date -Date $ExecuteTime -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Write-Host -Object "$($PSStyle.Bold)Commit/Execute Time:$($PSStyle.Reset) $CommitTime"
[string[]]$ConditionsAvailable = @('any', "day_$($ExecuteTime.Day)", "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())")
if ($InputFlags.Length -gt 0) {
	foreach ($Item in ($InputFlags -split ';' | ForEach-Object -Process {
		return $_.Trim()
	} | Where-Object -FilterScript {
		return ($_.Length -gt 0)
	})) {
		$ConditionsAvailable += "flag_$Item"
	}
}
if ($InputSchedule.Length -gt 0) {
	$ConditionsAvailable += 'schedule'
	[string]$ScheduleHour = $InputSchedule -replace '^.+ (?<hour>.+) .+ .+ .+$', '${hour}'
	if ($ScheduleHour -match '^\d?\d$') {
		[string]$Condition = "hour_$ScheduleHour"
		$ConditionsAvailable += $Condition
		$ConditionsAvailable += "day_$($ExecuteTime.Day)_$Condition"
		$ConditionsAvailable += "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())_$Condition"
	} else {
		[string]$Condition = "hour_$($ExecuteTime.Hour)"
		$ConditionsAvailable += $Condition
		$ConditionsAvailable += "day_$($ExecuteTime.Day)_$Condition"
		$ConditionsAvailable += "weekday_$($ExecuteTime.DayOfWeek.GetHashCode())_$Condition"
	}
}
$ConditionsAvailable = ($ConditionsAvailable | Sort-Object -Unique)
Write-Host -Object "$($PSStyle.Bold)Conditions Available ($($ConditionsAvailable.Count)):$($PSStyle.Reset) $($ConditionsAvailable -join ', ')"
foreach ($AssetDirectory in @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures',
	'yara-rules'
)) {
	Write-Host -Object "At ``$AssetDirectory``."
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectory
	[string]$AssetIndexFileFullPath = Join-Path -Path $AssetRoot -ChildPath 'index.tsv'
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath $AssetIndexFileFullPath -Delimiter "`t"
	[string[]]$GitFinishSessions = @()
	for ($AssetIndexNumber = 0; $AssetIndexNumber -lt $AssetIndex.Count; $AssetIndexNumber++) {
		[pscustomobject]$AssetIndexItem = $AssetIndex[$AssetIndexNumber]
		Write-Host -Object "At ``$AssetDirectory/$($AssetIndexItem.Name)``."
		[bool]$ShouldUpdate = $false
		foreach ($Item in ($AssetIndexItem.UpdateCondition -split ';' | ForEach-Object -Process {
			return $_.Trim()
		} | Where-Object -FilterScript {
			return ($_.Length -gt 0)
		})) {
			if ($Item -iin $ConditionsAvailable) {
				$ShouldUpdate = $true
				break;
			}
		}
		if (
			$ShouldUpdate -eq $false -or
			(Get-Date -Date $AssetIndexItem.LastUpdateTime -AsUTC) -gt $BufferTime
		) {
			Write-Host -Object "No need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
			continue
		}
		Write-Host -Object "Need to update ``$AssetDirectory/$($AssetIndexItem.Name)``."
		if ($AssetIndexItem.UpdateMethod -eq 'Git') {
			[string]$GitName = ($AssetIndexItem.Location -split '[\\\/]')[0]
			[string]$GitSession = "$GitName::$($AssetIndexItem.Source)"
			if ($GitFinishSessions -icontains $GitSession) {
				Write-Host -Object "Skip update ``$AssetDirectory/$($AssetIndexItem.Name)``, repeated Git repository ``$($AssetIndexItem.Source)``."
			} else {
				Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via Git repository ``$($AssetIndexItem.Source)``."
				[string]$GitWorkingDirectoryRoot = Join-Path -Path $AssetRoot -ChildPath $GitName
				if (Test-Path -LiteralPath $GitWorkingDirectoryRoot) {
					Remove-Item -LiteralPath $GitWorkingDirectoryRoot -Recurse -Force -Confirm:$false
				}
				Set-Location -LiteralPath $AssetRoot
				try {
					Invoke-Expression -Command "git --no-pager clone --quiet --recurse-submodules `"$($AssetIndexItem.Source)`" `"$GitName`""
					Remove-Item -LiteralPath @(
						(Join-Path -Path $GitWorkingDirectoryRoot -ChildPath '.git'),
						(Join-Path -Path $GitWorkingDirectoryRoot -ChildPath '.github')
					) -Recurse -Force -Confirm:$false
					Get-ChildItem -LiteralPath $GitWorkingDirectoryRoot -Include @(
						'.dockerignore',
						'*.bat',
						'*.bmp',
						'*.db',
						'*.diff',
						'*.dll',
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
						'*.pdf',
						'*.png',
						'*.ps1',
						'*.psd1',
						'*.psm1',
						'*.py',
						'*.rar',
						'*.rb',
						'*.sh',
						'*.tar',
						'*.ts',
						'*.txt',
						'*.yml',
						'*.zip',
						'Dockerfile',
						'makefile',
						'Makefile'
					) -Recurse -Force | Remove-Item -Force -Confirm:$false
				} catch {
					Write-Host -Object "::warning::$_"
				}
				$GitFinishSessions += $GitSession
			}
		} elseif ($AssetIndexItem.UpdateMethod -eq 'WebRequest') {
			Write-Host -Object "Update ``$AssetDirectory/$($AssetIndexItem.Name)`` via web request ``$($AssetIndexItem.Source)``."
			[string]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $AssetIndexItem.Location
			[string]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
			if ((Test-Path -LiteralPath $OutFileRoot -PathType 'Container') -eq $false) {
				New-Item -Path $OutFileRoot -ItemType 'Directory' -Confirm:$false
			}
			Start-Sleep -Seconds 1
			try {
				Invoke-WebRequest -Uri $AssetIndexItem.Source -UseBasicParsing -MaximumRedirection 1 -MaximumRetryCount 3 -RetryIntervalSec 10 -Method 'Get' -OutFile $OutFileFullName
			} catch {
				Write-Host -Object "::warning::$_"
			}
			Start-Sleep -Seconds 1
		} else {
			Write-Host -Object "::warning::Cannot update ``$AssetDirectory/$($AssetIndexItem.Name)``, no available update method!"
		}
		$AssetIndex[$AssetIndexNumber].LastUpdateTime = $CommitTime
	}
	Write-Host -Object "At ``$AssetDirectory``."
	Set-Csv -LiteralPath $AssetIndexFileFullPath -InputObject $AssetIndex -Delimiter "`t"
}
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $CommitTime -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$CommitTime"
$ErrorActionPreference = $ErrorActionOriginalPreference
