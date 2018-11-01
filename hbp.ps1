<#
    .SYNOPSIS
        Hatena Blog Post - �͂Ăȃu���O�̃N���C�A���g

    .DESCRIPTION
        �͂Ăȃu���O�֋L���𓊍e���邽�߂̃N���C�A���g�R�}���h�ł�.
        ����N�����ɂ̓A�J�E���g���̓��͂��K�v�ł�.
        ���͂��ꂽ����%HOMEPATH%�z����_hbp.txt���쐬���ċL�^���܂�.
        (API KEY�͈Í�������܂�)

    .PARAMETER File
        �|�X�g����t�@�C�����ł�.
        �w�肵���t�@�C����1�s�ڂ͋L���̃^�C�g���ɂȂ�܂�.
        2�s�ڂ͓ǂݔ�΂���, 3�s�ڈȍ~���L���̓��e�ƂȂ�܂�.

    .PARAMETER Category
        �L���̃J�e�S�����w�肵�܂�.�J���}��؂�ŕ����w�肷�邱�Ƃ��ł��܂�.

    .PARAMETER Draft
        �������ۑ��̏ꍇ��$true���w�肵�܂�.�f�t�H���g��$true�ł�.

    .INPUTS
        �Ȃ�.�p�C�v���C������̓��͔͂�Ή��ł�.

    .OUTPUTS
        �|�X�g�ɐ��������ꍇ�͍쐬���ꂽ�L����W���o�͂֕\����, �X�e�[�^�X0�ŏI�����܂�.
        ���s�����ꍇ�̓X�e�[�^�X1�ŏI�����܂�.

    .EXAMPLE
        hbp.ps1 -File blog.txt -category "windows, �J����" -Draft $true

    .NOTES
        Author:twinbird
        LICENSE MIT

    .LINK
        http://developer.hatena.ne.jp/ja/documents/blog/apis/atom
#>

# �p�����[�^�錾
Param(
    [parameter(mandatory=$true)][string] $file,
    [string] $category,
    [bool] $draft = $true
)

# �G���[�������͒�~����
$ErrorActionPreference = "Stop"

# �A�J�E���g���Ǘ��N���X
class AccountConfiguration {
    [string]$HatenaID
    [string]$BlogID
    [string]$ApiKey

    AccountConfiguration() {
        $path = join-path ([Environment]::GetFolderPath("UserProfile")) "hbp.txt"
        if ((Test-Path $path) -eq $true) {
            $this.getConfiguration($path)
        } else {
            [AccountConfiguration]::CreateConfigurationFile($path)
            $this.getConfiguration($path)
        }
    }

    getConfiguration($fileName) {
	    $file = New-Object System.IO.StreamReader($fileName, [System.Text.Encoding]::UTF8)
        # hatena_id
	    if (($line = $file.ReadLine()) -ne $null)
	    {
	        $ary = $line.Split(":")
            $this.HatenaID = $ary[1]
	    }
        # blog_id
	    if (($line = $file.ReadLine()) -ne $null)
	    {
	        $ary = $line.Split(":")
            $this.BlogID = $ary[1]
	    }
        # api_key
	    if (($line = $file.ReadLine()) -ne $null)
	    {
	        $ary = $line.Split(":")
            $this.ApiKey = $ary[1]
	    }
	    $file.Close()
    }

    [string] ConfigStr() {
        return @"
hatena_id:$($this.HatenaID)
blog_id:$($this.BlogID)
api_key:$($this.ApiKey)
"@
    }

    static CreateConfigurationFile([string] $path) {
        Write-Host "�A�J�E���g������͂��Ă�������"
        $_hatenaID = Read-Host "�͂Ă�ID"
        $_blogID = read-Host "�u���OID"
        $_apiKey = Read-Host "API KEY" -AsSecureString | ConvertFrom-SecureString

        $config_file_str = @"
hatena_id:$($_hatenaID)
blog_id:$($_blogID)
api_key:$($_apiKey)
"@
        $config_file_str | Out-File $path -Encoding UTF8 -NoClobber
    }

    [System.Management.Automation.PSCredential] GetCredential() {
        $secpasswd = $this.ApiKey | ConvertTo-SecureString
        $cred = New-Object System.Management.Automation.PSCredential($this.HatenaID, $secpasswd)
        return $cred
    }
}

# Basic�F�؂ɂ��N���C�A���g�N���X
class HatenaBlogBasicAuthClient {

    [AccountConfiguration] $Account
    [string] $LastPostedURI

    HatenaBlogBasicAuthClient([AccountConfiguration] $ac) {
        $this.account = $ac
        $this.LastPostedURI = ""
    }

    [string] CreateURI() {
	    return "https://blog.hatena.ne.jp/$($this.Account.hatenaID)/$($this.Account.blogID)/atom/entry"
    }

    [xml] CreatePostXML([Entry] $entry) {
	    $categoryString = ""
	    foreach($category in $entry.Categories) {
	        $categoryString += "<category term=`"$($category)`" />"
	    }
        $draft = "yes"
        if ($entry.Draft -eq $false) {
            $draft = "no"
        }

	    $xmlDoc = @"
<?xml version=`"1.0`" encoding=`"utf-8`"?>
	<entry xmlns=`"http://www.w3.org/2005/Atom`"
	       xmlns:app=`"http://www.w3.org/2007/app`">
    <title>$($entry.Title)</title>
    <content type=`"text/plain`">$($entry.EntryBody)</content>
    $($categoryString)
    <app:control>
        <app:draft>$($draft)</app:draft>
    </app:control>
</entry>
"@
	    return [xml]$xmlDoc
    }

    [bool] PostEntry([Entry] $entry) {
        $response = try {
            $postBody = [System.Text.Encoding]::UTF8.GetBytes($this.CreatePostXML($entry).OuterXml)
            Invoke-WebRequest -Uri $this.CreateURI() -Method POST -Body $postBody -Credential $this.Account.GetCredential()
        } catch {
            Write-host "An exception was caught: $($_.Exception.Message)"
            $_.Exception.Response
        }
        if ([int]$response.BaseResponse.StatusCode -ne 201) {
            Write-host "Post failed"
            Write-host "Server Response Status Code is $($response.BaseResponse.StatusCode)"
            return $false
        }
        $this.LastPostedURI = $response.Headers['location']
        return $true
    }
}

# �G���g�����̊Ǘ��N���X
class Entry {
    [string] $Title
    [string] $EntryBody
    [bool] $Draft
    [string[]] $Categories

    Entry() {
        $this.initialize()
    }

    Entry([string] $filepath) {
        $this.initialize()
        $this.LoadFromFile($filepath)
    }

    initialize() {
        $this.Title = ""
        $this.EntryBody = ""
        $this.Draft = $true
        $this.Categories = @()
    }

    LoadFromFile([string] $filepath) {
        $file = New-Object System.IO.StreamReader($filepath, [System.Text.Encoding]::UTF8)
        # 1�s�ڂ̓^�C�g��
        if (($line = $file.ReadLine()) -ne $null) {
            $this.Title = $line
        }
        # 2�s�ڂ͓ǂݔ�΂�
        if (($line = $file.ReadLine()) -ne $null) {
        }
        # �c��̍s�͖{��
        $this.EntryBody = $file.ReadToEnd()
    }

    [string] CategoriesToString() {
        $retStr = ""
        foreach($category in $this.Categories) {
            $retStr += $category + ","
        }
        return $retStr.trimEnd(',')
    }

    [string] ToString() {
        $str = @"
$($this.Title)
-------------------------------------------------------------------
Draft: $($this.Draft) | Category: $($this.CategoriesToString())
-------------------------------------------------------------------
$($this.EntryBody)
"@
        return $str
    }
}

# �J�e�S���w���z��
$categories = $category.Split(',')
# �O��̋󔒂̓g�������Ă���
$categories = $categories | ForEach-Object -Process { $_.Trim() }

# �ݒ�t�@�C����Ǎ�
$ac = New-Object AccountConfiguration

# �|�X�g����N���C�A���g�N���X��p��
$client = New-Object HatenaBlogBasicAuthClient($ac)

# �G���g�������쐬
$FullFilePath = Resolve-Path $file
$entry = New-Object Entry($FullFilePath)
$entry.Categories = $categories

# �|�X�g����
$ret = $client.PostEntry($entry)

# ���ʏo��
if ($ret -eq $true) {
    Write-Host "Posted URI is $($client.LastPostedURI)"
}
