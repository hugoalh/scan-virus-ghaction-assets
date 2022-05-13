[string[]]$AssetsAvailable = @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures'
)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'get-csv.psm1') -Scope 'Local'
foreach ($Asset in $AssetsAvailable) {
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $Asset
	[pscustomobject[]]$AssetIndex = Get-Csv -LiteralPath (Join-Path -Path $AssetRoot -ChildPath 'index.tsv') -Delimiter "`t"
	foreach ($Item in $AssetIndex) {
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
		Start-Sleep -Seconds 2
	}
}
[string]$Timestamp = Get-Date -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
[string]$AssetsMetaDataFullName = Join-Path -Path $PSScriptRoot -ChildPath 'assets-metadata.json'
[hashtable]$AssetsMetaData = (Get-Content -LiteralPath $AssetsMetaDataFullName -Raw -Encoding 'UTF8NoBOM' | ConvertFrom-Json -AsHashtable -Depth 100)
$AssetsMetaData.timestamp = $Timestamp
Set-Content -LiteralPath $AssetsMetaDataFullName -Value (ConvertTo-Json -InputObject $AssetsMetaData -Depth 100 -Compress) -Confirm:$false -NoNewline -Encoding 'UTF8NoBOM'
Write-Host -Object "::set-output name=timestamp::$Timestamp"
