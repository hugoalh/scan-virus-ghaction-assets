[string]$ErrorActionOldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_csv.psm1') -Scope 'Local'
[ValidateNotNullOrEmpty()][string]$TriggeredBy = $env:INPUT_TRIGGEREDBY
[datetime]$ExecuteTime = Get-Date -AsUTC
[datetime]$BufferTime = (Get-Date -Date $ExecuteTime -AsUTC).AddMinutes(-30)
[string]$CommitTime = Get-Date -Date $ExecuteTime -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
foreach ($AssetDirectory in @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures',
	'yara-rules'
)) {
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectory
	[string]$AssetIndexFileFullPath = Join-Path -Path $AssetRoot -ChildPath 'index.tsv'
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath $AssetIndexFileFullPath -Delimiter "`t"
	[string[]]$GitFinishSessions = @()
	for ($AssetIndexNumber = 0; $AssetIndexNumber -lt $AssetIndex.Count; $AssetIndexNumber++) {
		[pscustomobject]$AssetIndexItem = $AssetIndex[$AssetIndexNumber]
		if (
			$TriggeredBy -notmatch $AssetIndexItem.UpdateCondition -or
			$BufferTime -lt (Get-Date -Date $AssetIndexItem.LastUpdateTime -AsUTC)
		) {
			continue
		}
		if ($AssetIndexItem.UpdateMethod -eq 'Git') {
			[string]$GitName = ($AssetIndexItem.Location -split '[\\\/]')[0]
			[string]$GitSession = "$GitName::$($AssetIndexItem.Source)"
			if ($GitFinishSessions -notcontains $GitSession) {
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
						'*.eml',
						'*.html',
						'*.py',
						'*.sh',
						'*.txt',
						'*.yml',
						'Dockerfile',
						'makefile',
						'Makefile'
					) -Recurse -Force | Remove-Item -Force -Confirm:$false
				} catch {
					Write-Warning -Message $_
				}
				$GitFinishSessions += $GitSession
			}
		} elseif ($AssetIndexItem.UpdateMethod -eq 'WebRequest') {
			[string]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $AssetIndexItem.Location
			[string]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
			if ((Test-Path -LiteralPath $OutFileRoot -PathType 'Container') -eq $false) {
				New-Item -Path $OutFileRoot -ItemType 'Directory' -Confirm:$false
			}
			Start-Sleep -Seconds 1
			try {
				Invoke-WebRequest -Uri $AssetIndexItem.Source -UseBasicParsing -MaximumRedirection 1 -MaximumRetryCount 3 -RetryIntervalSec 10 -Method 'Get' -OutFile $OutFileFullName
			} catch {
				Write-Warning -Message $_
			}
			Start-Sleep -Seconds 1
		} else {
			continue
		}
		$AssetIndex[$AssetIndexNumber].LastUpdateTime = $CommitTime
	}
	Set-Csv -LiteralPath $AssetIndexFileFullPath -InputObject $AssetIndex -Delimiter "`t"
}
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $CommitTime -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$CommitTime"
$ErrorActionPreference = $ErrorActionOldPreference
exit 0
