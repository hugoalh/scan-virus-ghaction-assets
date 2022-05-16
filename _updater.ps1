[string]$ErrorActionOldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_csv.psm1') -Scope 'Local'
[datetime]$BufferTime = (Get-Date -AsUTC).AddHours(-2)
[string]$TriggeredBy = $env:INPUT_TRIGGEREDBY
[string]$UFormatTimeISO = '%Y-%m-%dT%H:%M:%SZ'
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
			($TriggeredBy -notmatch $AssetIndexItem.UpdateCondition) -or
			($BufferTime -lt (Get-Date -Date $AssetIndexItem.LastUpdateTime -AsUTC))
		) {
			continue
		}
		if ($AssetIndexItem.UpdateMethod -eq 'Git') {
			[string]$GitSession = "Git::$($AssetIndexItem.Source)"
			if ($GitFinishSessions -notcontains $GitSession) {
				[string]$GitWorkingDirectory = Join-Path -Path $AssetRoot -ChildPath $AssetIndexItem.Location
				if (Test-Path -LiteralPath $GitWorkingDirectory) {
					Remove-Item -LiteralPath $GitWorkingDirectory -Recurse -Force -Confirm:$false
				}
				Set-Location -LiteralPath $AssetRoot
				try {
					Invoke-Expression -Command "git --no-pager clone --quiet --recurse-submodules `"$($AssetIndexItem.Source)`" `"$($AssetIndexItem.Location)`""
					Remove-Item -LiteralPath @(
						(Join-Path -Path $GitWorkingDirectory -ChildPath '.git'),
						(Join-Path -Path $GitWorkingDirectory -ChildPath '.github')
					) -Recurse -Force -Confirm:$false
					Get-ChildItem -LiteralPath $GitWorkingDirectory -Include @(
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
		$AssetIndex[$AssetIndexNumber].LastUpdateTime = Get-Date -UFormat $UFormatTimeISO -AsUTC
	}
	Set-Csv -LiteralPath $AssetIndexFileFullPath -InputObject $AssetIndex -Delimiter "`t"
}
[string]$CommitTime = Get-Date -UFormat $UFormatTimeISO -AsUTC
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $CommitTime -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$CommitTime"
$ErrorActionPreference = $ErrorActionOldPreference
