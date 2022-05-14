[string[]]$AssetsAvailable = @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures'
)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_get-csv.psm1') -Scope 'Local'
for ($AssetsAvailableIndex = 0; $AssetsAvailableIndex -lt $AssetsAvailable.Count; $AssetsAvailableIndex++) {
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $AssetsAvailable[$AssetsAvailableIndex]
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath (Join-Path -Path $AssetRoot -ChildPath 'index.tsv') -Delimiter "`t"
	for ($AssetItemIndex = 0; $AssetItemIndex -lt $AssetIndex.Count; $AssetItemIndex++) {
		[pscustomobject]$Item = $AssetIndex[$AssetItemIndex]
		[string]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $Item.Location
		[string]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
		if ((Test-Path -LiteralPath $OutFileRoot -PathType 'Container') -eq $false) {
			New-Item -Path $OutFileRoot -ItemType 'Directory'
		}
		try {
			Invoke-WebRequest -Uri $Item.Source -UseBasicParsing -OutFile $OutFileFullName
		} catch {
			Write-Warning -Message $_
		}
		if (($AssetsAvailableIndex -ne ($AssetsAvailable.Count - 1)) -and ($AssetItemIndex -ne ($AssetIndex.Count - 1))) {
			Start-Sleep -Seconds 2.5
		}
	}
}
[string]$Timestamp = Get-Date -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_timestamp.txt') -Value $Timestamp -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$Timestamp"
