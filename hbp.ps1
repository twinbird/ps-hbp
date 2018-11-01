<#
    .SYNOPSIS
        Hatena Blog Post - はてなブログのクライアント

    .DESCRIPTION
        はてなブログへ記事を投稿するためのクライアントコマンドです.
        初回起動時にはアカウント情報の入力が必要です.
        入力された情報は%HOMEPATH%配下に_hbp.txtを作成して記録します.
        (API KEYは暗号化されます)

    .PARAMETER File
        ポストするファイル名です.
        指定したファイルの1行目は記事のタイトルになります.
        2行目は読み飛ばされ, 3行目以降が記事の内容となります.

    .PARAMETER Category
        記事のカテゴリを指定します.カンマ区切りで複数指定することもできます.

    .PARAMETER Draft
        下書き保存の場合は$trueを指定します.デフォルトは$trueです.

    .INPUTS
        なし.パイプラインからの入力は非対応です.

    .OUTPUTS
        ポストに成功した場合は作成された記事を標準出力へ表示し, ステータス0で終了します.
        失敗した場合はステータス1で終了します.

    .EXAMPLE
        hbp.ps1 -File blog.txt -category "windows, 開発環境" -Draft $true

    .NOTES
        Author:twinbird
        LICENSE MIT

    .LINK
        http://developer.hatena.ne.jp/ja/documents/blog/apis/atom
#>

# パラメータ宣言
Param(
    [parameter(mandatory=$true)][string] $file,
    [string] $category,
    [bool] $draft = $true
)

# エラー発生時は停止する
$ErrorActionPreference = "Stop"

# アカウント情報管理クラス
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
        Write-Host "アカウント情報を入力してください"
        $_hatenaID = Read-Host "はてなID"
        $_blogID = read-Host "ブログID"
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

# Basic認証によるクライアントクラス
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

# エントリ情報の管理クラス
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
        # 1行目はタイトル
        if (($line = $file.ReadLine()) -ne $null) {
            $this.Title = $line
        }
        # 2行目は読み飛ばし
        if (($line = $file.ReadLine()) -ne $null) {
        }
        # 残りの行は本文
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

# カテゴリ指定を配列化
$categories = $category.Split(',')
# 前後の空白はトリムしておく
$categories = $categories | ForEach-Object -Process { $_.Trim() }

# 設定ファイルを読込
$ac = New-Object AccountConfiguration

# ポストするクライアントクラスを用意
$client = New-Object HatenaBlogBasicAuthClient($ac)

# エントリ情報を作成
$FullFilePath = Resolve-Path $file
$entry = New-Object Entry($FullFilePath)
$entry.Categories = $categories

# ポストする
$ret = $client.PostEntry($entry)

# 結果出力
if ($ret -eq $true) {
    Write-Host "Posted URI is $($client.LastPostedURI)"
}
