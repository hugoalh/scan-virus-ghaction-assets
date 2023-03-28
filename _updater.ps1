#Requires -PSEdition Core -Version 7.2
$Script:ErrorActionPreference = 'Stop'
Import-Module -Name 'hugoalh.GitHubActionsToolkit' -Scope 'Local'
Write-Host -Object 'Initialize.'
$CurrentWorkingDirectory = Get-Location
[String[]]$GitIgnores = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '_updater_gitignore.txt') -Encoding 'UTF8NoBOM' |
	Where-Object -FilterScript { $_.Length -igt 0 }
[Hashtable]$ImportCsvParameters_Tsv = @{
	Delimiter = "`t"
	Encoding = 'UTF8NoBOM'
}
[String]$MetadataFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'metadata.json'
[DateTime]$TimeInvoke = Get-Date -AsUTC
[DateTime]$TimeBuffer = $TimeInvoke.AddHours(-1)
[String]$TimeCommit = Get-Date -Date $TimeInvoke -UFormat '%Y-%m-%dT%H:%M:%SZ' -AsUTC
Write-Host -Object "$($PSStyle.Bold)Timestamp: $($PSStyle.Reset)$TimeCommit"
Function ConvertTo-JsonTabIndent {
	[CmdletBinding()]
	[OutputType([String])]
	Param (
		[Parameter(Mandatory = $True, Position = 0)][Alias('Input', 'Object')]$InputObject
	)
	(ConvertTo-Json -InputObject $InputObject -Depth 100) -isplit '\r?\n' |
		ForEach-Object -Process {
			If ($_ -imatch '^(?:  )+') {
				$_ -ireplace "^$($Matches[0])", ("`t" * ($Matches[0].Length / 2)) |
					Write-Output
			}
			Else {
				Write-Output -InputObject $_
			}
		} |
		Join-String -Separator "`n"
}
Write-Host -Object 'Update assets.'
ForEach ($AssetDirectoryName In @('clamav-unofficial', 'yara')) {
	[String]$AssetDirectoryPath = Join-Path -Path $PSScriptRoot -ChildPath $AssetDirectoryName
	Write-Host -Object "Read ``$AssetDirectoryName`` asset index."
	[String]$AssetIndexFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath 'index.tsv'
	[PSCustomObject[]]$AssetIndex = Import-Csv -LiteralPath $AssetIndexFilePath @ImportCsvParameters_Tsv
	For ($AssetIndexRow = 0; $AssetIndexRow -ilt $AssetIndex.Count; $AssetIndexRow++) {
		[PSCustomObject]$AssetIndexItem = $AssetIndex[$AssetIndexRow]
		If ($AssetIndexItem.Group.Length -igt 0) {
			Continue
		}
		Enter-GitHubActionsLogGroup -Title "At ``$AssetDirectoryName/$($AssetIndexItem.Name)``."
		If ((Get-Date -Date $AssetIndexItem.Timestamp -AsUTC) -igt $TimeBuffer) {
			Write-Host -Object 'No need to update.'
			Exit-GitHubActionsLogGroup
			Continue
		}
		Write-Host -Object 'Need to update.'
		If ($AssetIndexItem.Remote -imatch '^https:\/\/github\.com\/[\da-z_.-]+\/[\da-z_.-]+\.git$') {
			[String]$GitWorkingDirectoryName = $AssetIndexItem.Path -isplit '[\\\/]' |
				Select-Object -First 1
			[String]$GitWorkingDirectoryPath = Join-Path -Path $AssetDirectoryPath -ChildPath $GitWorkingDirectoryName
			If (Test-Path -LiteralPath $GitWorkingDirectoryPath) {
				Write-Host -Object "Remove old assets."
				Remove-Item -LiteralPath $GitWorkingDirectoryPath -Recurse -Force -Confirm:$False
			}
			Write-Host -Object "Update via Git repository ``$($AssetIndexItem.Remote)``."
			Set-Location -LiteralPath $AssetDirectoryPath
			Try {
				Invoke-Expression -Command "git --no-pager clone --recurse-submodules `"$($AssetIndexItem.Remote)`" `"$GitWorkingDirectoryName`""
			}
			Catch {
				Write-GitHubActionsWarning -Message $_
			}
			Set-Location -LiteralPath $CurrentWorkingDirectory.Path
			Get-ChildItem -LiteralPath $GitWorkingDirectoryPath -Include $GitIgnores -Recurse -Force |
				ForEach-Object -Process {
					Try {
						Remove-Item -LiteralPath $_.FullName -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
					}
					Catch {
						Write-Warning -Message $_
					}
				}
		}
		Else {
			Write-Host -Object "Update via web request ``$($AssetIndexItem.Remote)``."
			[String]$OutFilePath = Join-Path -Path $AssetDirectoryPath -ChildPath $AssetIndexItem.Path
			[String]$OutFilePathParent = Split-Path -Path $OutFilePath -Parent
			If (!(Test-Path -LiteralPath $OutFilePathParent -PathType 'Container')) {
				$Null = New-Item -Path $OutFilePathParent -ItemType 'Directory' -Confirm:$False
			}
			Try {
				Invoke-WebRequest -Uri $AssetIndexItem.Remote -UseBasicParsing -MaximumRedirection 5 -MaximumRetryCount 5 -RetryIntervalSec 10 -Method 'Get' -OutFile $OutFilePath
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
		Export-Csv -LiteralPath $AssetIndexFilePath @ImportCsvParameters_Tsv -NoTypeInformation -UseQuotes 'AsNeeded' -Confirm:$False
}
Write-Host -Object 'Update metadata.'
[PSCustomObject]$Metadata = Get-Content -LiteralPath $MetadataFilePath -Raw -Encoding 'UTF8NoBOM' |
	ConvertFrom-Json -Depth 100
$Metadata.Timestamp = $TimeCommit
Set-Content -LiteralPath $MetadataFilePath -Value (ConvertTo-JsonTabIndent -InputObject $Metadata) -Confirm:$False -Encoding 'UTF8NoBOM'
Write-Host -Object 'Conclusion.'
Set-GitHubActionsOutput -Name 'timestamp' -Value $TimeCommit
