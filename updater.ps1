#Requires -PSEdition Core -Version 7.2
$Script:ErrorActionPreference = 'Stop'
Import-Module -Name 'hugoalh.GitHubActionsToolkit' -Scope 'Local'
Test-GitHubActionsEnvironment -Mandatory
Write-Host -Object 'Initialize.'
$CurrentWorkingDirectory = [System.Environment]::CurrentDirectory
[String[]]$GitIgnores = @(
	'.cfduplication.*',
	'.dockerignore',
	'.eslintrc.*',
	'.git',
	'.github',
	'.markdownlint.*',
	'.vscode',
	'.vscodeignore',
	'.yamllint.*',
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
	'*.diff',
	'*.dll',
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
	'*.sql',
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
	'Dockerfile',
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
Write-Host -Object 'Update assets.'
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
	[String]$AssetDirectoryPath = Join-Path -Path $PSScriptRoot -ChildPath $AssetTypeMeta.Path
	[String]$AssetIndexFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Import-Csv -LiteralPath $AssetIndexFilePath @TsvParameters
	For ([UInt64]$AssetIndexRow = 0; $AssetIndexRow -lt $AssetIndex.Count; $AssetIndexRow += 1) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexRow]
		If ($AssetIndexItem.Group.Length -gt 0) {
			Continue
		}
		Enter-GitHubActionsLogGroup -Title "At ``$($AssetTypeMeta.Name)/$($AssetIndexItem.Name)``."
		If ((Get-Date -Date $AssetIndexItem.Timestamp -AsUTC) -gt $TimeBuffer) {
			Write-Host -Object 'No need to update.'
			Exit-GitHubActionsLogGroup
			Continue
		}
		If ($AssetIndexItem.Remote -imatch '^https?:\/\/.+?\.git$') {
			Write-Host -Object "Update via clone Git repository ``$($AssetIndexItem.Remote)``."
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
			Write-Host -Object "Update via web request ``$($AssetIndexItem.Remote)``."
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
		Exit-GitHubActionsLogGroup
	}
	Write-Host -Object "Update ``$AssetDirectoryName`` asset index."
	$AssetIndex |
		Export-Csv -LiteralPath $AssetIndexFilePath @TsvParameters -UseQuotes 'AsNeeded' -Confirm:$False
}
Write-Host -Object 'Verify assets index.'
[String[]]$IndexIssuesFileNotExist = @()
[String[]]$IndexIssuesFileNotRecord = @()
ForEach ($AssetDirectoryName In $AssetsDirectoryNames) {
	[String]$AssetDirectoryPath = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectoryName
	Write-Host -Object "Read ``$AssetDirectoryName`` asset index."
	[String]$AssetIndexFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Import-Csv -LiteralPath $AssetIndexFilePath @TsvParameters
	For ([UInt64]$AssetIndexRow = 0; $AssetIndexRow -lt $AssetIndex.Count; $AssetIndexRow += 1) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexRow]
		If ($AssetIndexItem.Type -ieq 'Group') {
			Continue
		}
		If (Test-Path -LiteralPath (Join-Path -Path $AssetDirectoryPath -ChildPath $AssetIndexItem.Path) -PathType 'Leaf') {
			Continue
		}
		$IndexIssuesFileNotExist += "$AssetDirectoryName/$($AssetIndexItem.Name)"
	}
	If ($AssetDirectoryName -ieq 'yara') {
		ForEach ($ElementFullName In (
			Get-ChildItem -LiteralPath @(
				(Join-Path -Path $AssetDirectoryPath -ChildPath 'bartblaze' -AdditionalChildPath @('rules')),
				(Join-Path -Path $AssetDirectoryPath -ChildPath 'neo23x0' -AdditionalChildPath @('yara'))
			) -Include @('*.yar', '*.yara') -Recurse -File |
				Select-Object -ExpandProperty 'FullName'
		)) {
			[String]$ElementRelativeName = $ElementFullName -ireplace "^$([RegEx]::Escape($AssetDirectoryPath))[\\\/]", '' -ireplace '[\\\/]', '/'
			If ($AssetIndex.Path -inotcontains $ElementRelativeName) {
				$IndexIssuesFileNotRecord += $ElementRelativeName
			}
		}
	}
}
If ($IndexIssuesFileNotExist.Count -gt 0) {
	Write-GitHubActionsWarning -Message @"
File Not Exist [$($IndexIssuesFileNotExist.Count)]:

$(
	$IndexIssuesFileNotExist |
		Sort-Object |
		Join-String -Separator "`n" -FormatString '- `{0}`'
)
"@
}
If ($IndexIssuesFileNotRecord -gt 0) {
	Write-GitHubActionsWarning -Message @"
File Not Record [$($IndexIssuesFileNotRecord.Count)]:

$(
	$IndexIssuesFileNotRecord |
		Sort-Object |
		Join-String -Separator "`n" -FormatString '- `{0}`'
)
"@
}
