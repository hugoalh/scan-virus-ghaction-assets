[string]$ErrorActionPreferenceOld = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_csv.psm1') -Scope 'Local'
[datetime]$BufferTime = (Get-Date -AsUTC).AddHours(-2)
[string]$TimestampIndexFullPath = Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.tsv'
[hashtable]$TimestampIndex = @{}
Get-Csv -LiteralPath $TimestampIndexFullPath -Delimiter "`t" | ForEach-Object -Process {
	$TimestampIndex[$_.Element] = Get-Date -Date $_.Time -AsUTC
}
[string]$TriggeredBy = $env:INPUT_TRIGGEREDBY
[string]$UFormatTimeISO = '%Y-%m-%dT%H:%M:%SZ'
foreach ($AssetCategoryDirectory in @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures',
	'yara-rules'
)) {
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetCategoryDirectory
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath (Join-Path -Path $AssetRoot -ChildPath 'index.tsv') -Delimiter "`t"
	$AssetIndex | Where-Object -FilterScript {
		return (($_.UpdateMethod -eq 'Git') -and ($TriggeredBy -match $_.UpdateCondition) -and ($BufferTime -gt ($TimestampIndex["$AssetCategoryDirectory/$($_.Name)"] ?? (Get-Date -Date 0 -AsUTC))))
	} | ForEach-Object -Process {
		return ConvertTo-Json -InputObject ([ordered]@{
			Location = ($_.Location -split '[\\\/]')[0]
			Source = $_.Source
		}) -Depth 100 -Compress
	} | Select-Object -Unique | ForEach-Object -Process {
		[hashtable]$Item = ConvertFrom-Json -InputObject $_ -AsHashtable -Depth 100
		[string]$GitWorkingDirectory = Join-Path -Path $AssetRoot -ChildPath $Item.Location
		if (Test-Path -LiteralPath $GitWorkingDirectory) {
			Remove-Item -LiteralPath $GitWorkingDirectory -Recurse -Force -Confirm:$false
		}
		Set-Location -LiteralPath $AssetRoot
		try {
			Invoke-Expression -Command "git --no-pager clone --quiet --recurse-submodules `"$($Item.Source)`" `"$($Item.Location)`""
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
		$script:TimestampIndex["$AssetCategoryDirectory/$($_.Name)"] = Get-Date -AsUTC
		Set-Location -LiteralPath $PSScriptRoot
	}
	$AssetIndex | Where-Object -FilterScript {
		return (($_.UpdateMethod -eq 'WebRequest') -and ($TriggeredBy -match $_.UpdateCondition) -and ($BufferTime -gt ($TimestampIndex["$AssetCategoryDirectory/$($_.Name)"] ?? (Get-Date -Date 0 -AsUTC))))
	} | ForEach-Object -Process {
		[string]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $_.Location
		[string]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
		if ((Test-Path -LiteralPath $OutFileRoot -PathType 'Container') -eq $false) {
			New-Item -Path $OutFileRoot -ItemType 'Directory' -Confirm:$false
		}
		Start-Sleep -Seconds 1
		try {
			Invoke-WebRequest -Uri $_.Source -UseBasicParsing -MaximumRedirection 1 -MaximumRetryCount 3 -RetryIntervalSec 5 -Method 'Get' -OutFile $OutFileFullName
		} catch {
			Write-Warning -Message $_
		}
		Start-Sleep -Seconds 1
		$script:TimestampIndex["$AssetCategoryDirectory/$($_.Name)"] = Get-Date -AsUTC
	}
}
[datetime]$CommitTime = Get-Date -AsUTC
$TimestampIndex['_commit'] = $CommitTime
Set-Csv -LiteralPath $TimestampIndexFullPath -InputObject ([pscustomobject[]]($TimestampIndex.GetEnumerator() | ForEach-Object -Process {
	return [pscustomobject]@{
		Element = $_.Name
		Time = Get-Date -Date $_.Value -UFormat $UFormatTimeISO -AsUTC
	}
}) | Sort-Object -Property 'Element') -Delimiter "`t"
Write-Host -Object "::set-output name=timestamp::$(Get-Date -Date $CommitTime -UFormat $UFormatTimeISO -AsUTC)"
$ErrorActionPreference = $ErrorActionPreferenceOld
