[string[]]$AssetsAvailable = @(
	'clamav-signatures-ignore-presets',
	'clamav-unofficial-signatures'
)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'get-csv.psm1') -Scope 'Local'
foreach ($Asset in $AssetsAvailable) {
	[string]$AssetRoot = Join-Path -Path $PSScriptRoot -ChildPath $Asset
	[pscustomobject[]]$AssetIndex = Get-Csv -Path (Join-Path -Path $AssetRoot -ChildPath 'index.tsv') -Delimiter "`t"
	foreach ($Item in $AssetIndex) {
		[string]$OutFileFullName = Join-Path -Path $AssetRoot -ChildPath $Item.Location
		[string]$OutFileRoot = Split-Path -Path $OutFileFullName -Parent
		if ((Test-Path -Path $OutFileRoot) -eq $false) {
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
