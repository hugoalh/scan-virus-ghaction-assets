[hashtable[]]$AssetsAvailable = @(
	@{ Path = 'clamav-signatures-ignore-presets'; UpdateCondition = '^.+$' },
	@{ Path = 'clamav-unofficial-signatures'; UpdateCondition = '^.+$' },
	@{ Path = 'yara-rules'; UpdateCondition = '^workflow_dispatch$' }
)
[string]$TriggeredBy = $env:INPUT_TRIGGEREDBY
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_get-csv.psm1') -Scope 'Local'
foreach ($AssetAvailable in $AssetsAvailable) {
	if ($TriggeredBy -notmatch $AssetAvailable.UpdateCondition) {
		continue
	}
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetAvailable.Path
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath (Join-Path -Path $AssetRoot -ChildPath 'index.tsv') -Delimiter "`t"
	$AssetIndex | Where-Object -FilterScript {
		return ($_.UpdateMethod -eq 'Git')
	} | ForEach-Object -Process {
		return ConvertTo-Json -InputObject [ordered]@{
			Location = ($_.Location -split '[\\\/]')[0]
			Source = $_.Source
		} -Depth 100 -Compress
	} | Select-Object -Unique | ForEach-Object -Process {
		[hashtable]$Item = ConvertFrom-Json -InputObject $_ -AsHashtable -Depth 100
		[string]$GitWorkingDirectory = Join-Path -Path $AssetRoot -ChildPath $Item.Location
		if (Test-Path -LiteralPath $GitWorkingDirectory) {
			Remove-Item -LiteralPath $GitWorkingDirectory -Recurse -Force -Confirm:$false
		}
		Set-Location -LiteralPath $AssetRoot
		try {
			Invoke-Expression -Command "git --no-pager clone --no-tags --quiet --recurse-submodules `"$($Item.Source)`" `"$($Item.Location)`""
			Remove-Item -LiteralPath (Join-Path -Path $GitWorkingDirectory -ChildPath '.git') -Recurse -Force -Confirm:$false
		} catch {
			Write-Warning -Message $_
		}
		Set-Location -LiteralPath $PSScriptRoot
	}
	$AssetIndex | Where-Object -FilterScript {
		return ($_.UpdateMethod -eq 'WebRequest')
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
	}
}
[string]$Timestamp = Get-Date -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $Timestamp -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$Timestamp"
