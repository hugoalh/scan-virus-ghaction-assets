#Requires -PSEdition Core -Version 7.2
$Script:ErrorActionPreference = 'Stop'
Import-Module -Name 'hugoalh.GitHubActionsToolkit' -Scope 'Local'
Test-GitHubActionsEnvironment -Mandatory
Write-Host -Object 'Initialize.'
$CurrentWorkingDirectory = [System.Environment]::CurrentDirectory
[String[]]$ClamAVAllowExtensions = @(
	'*.cat',
	'*.cbc',
	'*.cdb',
	'*.crb',
	'*.fp',
	'*.ftm',
	'*.gdb',
	'*.hdb',
	'*.hdu',
	'*.hsb',
	'*.hsu',
	'*.idb',
	'*.ign',
	'*.ign2',
	'*.info',
	'*.ldb',
	'*.ldu',
	'*.mdb',
	'*.mdu',
	'*.msb',
	'*.msu',
	'*.ndb',
	'*.ndu',
	'*.pdb',
	'*.pwdb',
	'*.sfp',
	'*.wdb',
	'*.yar',
	'*.yara'
)
[String[]]$YaraAllowExtensions = @(
	'*.yar',
	'*.yara'
)
[String[]]$GitIgnores = @(
	'*.[0-9][0-9][0-9]',
	'*.ai',
	'*.alz',
	'*.bat',
	'*.bin',
	'*.bmp',
	'*.cab',
	'*.cjs',
	'*.cpuprofile',
	'*.db',
	'*.deb',
	'*.diff',
	'*.dll',
	'*.[Dd]ockerfile',
	'*.egg',
	'*.eml',
	'*.exe',
	'*.gif',
	'*.gz',
	'*.gzip',
	'*.html',
	'*.iso',
	'*.jpeg',
	'*.jpg',
	'*.js',
	'*.json',
	'*.lnk',
	'*.log',
	'*.mjs',
	'*.msi',
	'*.msix',
	'*.msixbundle',
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
	'*.rpm',
	'*.sh',
	'*.sql',
	'*.svg',
	'*.tar',
	'*.tar.gz',
	'*.tar.gzip',
	'*.tgz',
	'*.tmp',
	'*.ts',
	'*.txt',
	'*.xml',
	'*.xps',
	'*.yaml',
	'*.yml',
	'*.zip',
	'.cfduplication.*',
	'.dockerignore',
	'.eslintrc.*',
	'.git',
	'.github',
	'.markdownlint.*',
	'.vscode',
	'.vscodeignore',
	'.yamllint.*',
	'[Dd]ockerfile',
	'[Mm]akefile'
)
[Hashtable]$TsvParameters = @{
	Delimiter = "`t"
	Encoding = 'UTF8NoBOM'
}
[DateTime]$TimeInvoke = Get-Date -AsUTC
[DateTime]$TimeBuffer = $TimeInvoke.AddHours(-1)
[String]$TimeCommit = Get-Date -Date $TimeInvoke -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Write-Host -Object "Timestamp: $TimeCommit"
Set-GitHubActionsOutput -Name 'timestamp' -Value $TimeCommit
[PSCustomObject[]]$AssetsTypeMeta = @(
	[PSCustomObject]@{
		Name = 'ClamAV'
		Path = 'clamav'
	},
	[PSCustomObject]@{
		Name = 'YARA'
		Path = 'yara'
	}
)
ForEach ($AssetTypeMeta In $AssetsTypeMeta) {
	Write-Host -Object "Read $($AssetTypeMeta.Name) asset index."
	[String]$AssetDirectoryPath = Join-Path -Path $CurrentWorkingDirectory -ChildPath $AssetTypeMeta.Path
	[String]$AssetIndexFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Import-Csv -LiteralPath $AssetIndexFilePath @TsvParameters
	For ([UInt64]$AssetIndexRow = 0; $AssetIndexRow -lt $AssetIndex.Count; $AssetIndexRow += 1) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexRow]
		If (
			$AssetIndexItem.Type -iin @('Unusable') -or
			$AssetIndexItem.Group.Length -gt 0
		) {
			Continue
		}
		If ((Get-Date -Date $AssetIndexItem.Timestamp -AsUTC) -gt $TimeBuffer) {
			Write-Host -Object "No need to update asset ``$($AssetTypeMeta.Name)/$($AssetIndexItem.Name)``."
			Continue
		}
		If ($AssetIndexItem.Remote -imatch '^https?:\/\/.+?\.git$') {
			Write-Host -Object "Need to update asset ``$($AssetTypeMeta.Name)/$($AssetIndexItem.Name)`` via clone Git repository ``$($AssetIndexItem.Remote)``."
			[String]$GitWorkingDirectoryName = $AssetIndexItem.Path -isplit '[\\\/]' |
				Select-Object -Index 0
			[String]$GitWorkingDirectoryPath = Join-Path -Path $AssetDirectoryPath -ChildPath $GitWorkingDirectoryName
			If (Test-Path -LiteralPath $GitWorkingDirectoryPath) {
				Remove-Item -LiteralPath $GitWorkingDirectoryPath -Recurse -Force -Confirm:$False
			}
			Set-Location -LiteralPath $AssetDirectoryPath
			Try {
				git --no-pager clone --depth 1 $AssetIndexItem.Remote $GitWorkingDirectoryName
			}
			Catch {
				Write-GitHubActionsWarning -Message $_
			}
			Set-Location -LiteralPath $CurrentWorkingDirectory
			Get-ChildItem -LiteralPath $GitWorkingDirectoryPath -Include $GitIgnores -Recurse -Force |
				Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
		}
		Else {
			Write-Host -Object "Need to update asset ``$($AssetTypeMeta.Name)/$($AssetIndexItem.Name)`` via web request ``$($AssetIndexItem.Remote)``."
			[String]$OutFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath $AssetIndexItem.Path
			[String]$OutFilePathParent = Split-Path -Path $OutFilePath -Parent
			If (!(Test-Path -LiteralPath $OutFilePathParent -PathType 'Container')) {
				$Null = New-Item -Path $OutFilePathParent -ItemType 'Directory' -Confirm:$False
			}
			Try {
				Invoke-WebRequest -Uri $AssetIndexItem.Remote -MaximumRedirection 1 -MaximumRetryCount 2 -RetryIntervalSec 5 -Method 'Get' -OutFile $OutFilePath
			}
			Catch {
				Write-GitHubActionsWarning -Message $_
			}
		}
		$AssetIndex[$AssetIndexRow].Timestamp = $TimeCommit
	}
	Write-Host -Object "Update $($AssetTypeMeta.Name) asset index."
	$AssetIndex |
		Export-Csv -LiteralPath $AssetIndexFilePath @TsvParameters -UseQuotes 'AsNeeded' -Confirm:$False
	For ([UInt64]$AssetIndexRow = 0; $AssetIndexRow -lt $AssetIndex.Count; $AssetIndexRow += 1) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexRow]
		[String]$AssetIndexItemFullPath = Join-Path -Path $AssetDirectoryPath -ChildPath $AssetIndexItem.Path
		If ($AssetIndexItem.Type -ieq 'Group') {
			If ($AssetsTypeMeta.Path -ieq 'clamav') {
				[String[]]$AllowExtensions = $ClamAVAllowExtensions
			} ElseIf ($AssetsTypeMeta.Path -ieq 'yara') {
				[String[]]$AllowExtensions = $YaraAllowExtensions
			} Else {
				Continue
			}
			ForEach ($ElementRelativeName In (
				Get-ChildItem -LiteralPath $AssetIndexItemFullPath -Include $AllowExtensions -Recurse -File |
					Select-Object -ExpandProperty 'FullName' |
					ForEach-Object -Process { $_ -ireplace "^$([RegEx]::Escape($AssetDirectoryPath))[\\/]", '' -ireplace '[\\/]', '/' }
			)) {
				If ($AssetIndex.Path -inotcontains $ElementRelativeName) {
					Write-GitHubActionsWarning -Message "Asset ``$($AssetTypeMeta.Name)/$ElementRelativeName`` is not record!"
				}
			}
			Continue
		}
		If ($AssetIndexItem.Type -iin @('Unusable')) {
			If (Test-Path -LiteralPath $AssetIndexItemFullPath -PathType 'Leaf') {
				Remove-Item -LiteralPath $AssetIndexItemFullPath -Recurse -Force -Confirm:$False
			}
			Continue
		}
		If (!(Test-Path -LiteralPath $AssetIndexItemFullPath -PathType 'Leaf')) {
			Write-GitHubActionsWarning -Message "Asset ``$($AssetTypeMeta.Name)/$($AssetIndexItem.Name)`` is not exist!"
			Continue
		}
	}
}
