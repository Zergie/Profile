Param
(
    [Parameter(
               ValueFromPipelineByPropertyName=$true)]
    [string]
    $Address,

    [Parameter(
               ValueFromPipelineByPropertyName=$true)]
    [string]
    $Username,

    [Parameter(
               ValueFromPipelineByPropertyName=$true)]
    [string]
    $Password,

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string]
    $Name,

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string]
    $Gateway,

    [switch]
    $FullScreen,

    [switch]
    $DoNotConnect,


    [int] $Width = 1430,
    [int] $Height = 800,
    [int] $UseMultimon = 0,
    [int] $SessionBpp = 32,
    [int] $Compression = 1,
    [int] $Keyboardhook = 2,
    [int] $Audiocapturemode = 0,
    [int] $Videoplaybackmode = 1,
    [int] $ConnectionType = 7,
    [int] $Networkautodetect = 1,
    [int] $Bandwidthautodetect = 1,
    [int] $Displayconnectionbar = 1,
    [int] $Enableworkspacereconnect = 0,
    [int] $DisableWallpaper = 0,
    [int] $AllowFontSmoothing = 0,
    [int] $AllowDesktopComposition = 0,
    [int] $DisableFullWindowDrag = 1,
    [int] $DisableMenuAnims = 1,
    [int] $DisableThemes = 0,
    [int] $DisableCursorSetting = 0,
    [int] $Bitmapcachepersistenable = 1,
    [int] $Audiomode = 0,
    [int] $Redirectprinters = 1,
    [int] $Redirectcomports = 0,
    [int] $Redirectsmartcards = 1,
    [int] $Redirectclipboard = 1,
    [int] $Redirectposdevices = 0,
    [int] $AutoreconnectionEnabled = 1,
    [int] $AuthenticationLevel = 2,
    [int] $PromptForCredentials = 0,
    [int] $NegotiateSecurityLayer = 1,
    [string] $AlternateShell = "",
    [string] $ShellWorkingDirectory = "",
    [int] $Gatewayusagemethod = 2,
    [int] $Gatewaycredentialssource = 4,
    [int] $Gatewayprofileusagemethod = 1,
    [int] $Promptcredentialonce = 1,
    [int] $Gatewaybrokeringtype = 0,
    [int] $UseRedirectionServerName = 0,
    [int] $Rdgiskdcproxy = 0,
    [string] $Kdcproxyname = "",
    [string] $Drivestoredirect = "",
    [int] $ConnectToConsole = 1,
    [string] $RemoteApplicationCmdline = "",
    [switch] $RemoteApplicationExpandcmdline,
    [switch] $RemoteApplicationExpandworkingdir,
    [string] $RemoteApplicationFile = "",
    [string] $RemoteApplicationIcon = "",
    [switch] $RemoteApplicationMode,
    [string] $RemoteApplicationName = "",
    [string] $RemoteApplicationProgram = "",


    [Parameter(Mandatory=$false,
               ValueFromRemainingArguments=$true)]
    [string] $AdditionalArguments
)
dynamicparam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Type
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "TypeParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
            ConvertFrom-Json |
            ForEach-Object Connect-RDPSession |
            Get-Member -Type NoteProperty |
            ForEach-Object Name
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Type", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}

Process {
    $Type = $PSBoundParameters.Type

    if ($null -ne $Type) {
        $json = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object Connect-RDPSession |
                    ForEach-Object $Type

        $Address=$json.Address
        $Username=$json.Username
        $Password=$json.Password
        $Gateway=$json.Gateway
    }
    if ($Name.Length -eq 0) {
        $Name = [string]::new((
                $Type.ToCharArray() |
                Where-Object { $_ -notin [System.IO.Path]::GetInvalidFileNameChars()}
            ))
    }
    if ($Name.Length -eq 0) {
        $Name = [string]::new((
                $Address.ToCharArray() |
                Where-Object { $_ -notin [System.IO.Path]::GetInvalidFileNameChars()}
            ))
    }

    if ($DoNotConnect) {
        [pscustomobject]@{
            Type=$Type
            Address=$Address
            Username=$Username
            Password=$Password
            Gateway=$Gateway
        }
    } else {
        "screen mode id:i:$(if ($FullScreen) { 2 } else { 1 })
        use multimon:i:$UseMultimon
        desktopwidth:i:$Width
        desktopheight:i:$Height
        session bpp:i:$SessionBpp
        compression:i:$Compression
        keyboardhook:i:$Keyboardhook
        audiocapturemode:i:$Audiocapturemode
        videoplaybackmode:i:$Videoplaybackmode
        connection type:i:$ConnectionType
        networkautodetect:i:$Networkautodetect
        bandwidthautodetect:i:$Bandwidthautodetect
        displayconnectionbar:i:$Displayconnectionbar
        enableworkspacereconnect:i:$Enableworkspacereconnect
        disable wallpaper:i:$DisableWallpaper
        allow font smoothing:i:$AllowFontSmoothing
        allow desktop composition:i:$AllowDesktopComposition
        disable full window drag:i:$DisableFullWindowDrag
        disable menu anims:i:$DisableMenuAnims
        disable themes:i:$DisableThemes
        disable cursor setting:i:$DisableCursorSetting
        bitmapcachepersistenable:i:$Bitmapcachepersistenable
        full address:s:$Address
        username:s:$Username
        audiomode:i:$Audiomode
        redirectprinters:i:$Redirectprinters
        redirectcomports:i:$Redirectcomports
        redirectsmartcards:i:$Redirectsmartcards
        redirectclipboard:i:$Redirectclipboard
        redirectposdevices:i:$Redirectposdevices
        autoreconnection enabled:i:$AutoreconnectionEnabled
        authentication level:i:$AuthenticationLevel
        prompt for credentials:i:$PromptForCredentials
        negotiate security layer:i:$NegotiateSecurityLayer
        remoteapplicationmode:i:$(if ($RemoteApplicationMode) { 1 } else { 0 })
        alternate shell:s:$AlternateShell
        shell working directory:s:$ShellWorkingDirectory
        gatewayhostname:s:$Gateway
        gatewayusagemethod:i:$Gatewayusagemethod
        gatewaycredentialssource:i:$Gatewaycredentialssource
        gatewayprofileusagemethod:i:$Gatewayprofileusagemethod
        promptcredentialonce:i:$Promptcredentialonce
        gatewaybrokeringtype:i:$Gatewaybrokeringtype
        use redirection server name:i:$UseRedirectionServerName
        rdgiskdcproxy:i:$Rdgiskdcproxy
        kdcproxyname:s:$Kdcproxyname
        drivestoredirect:s:$Drivestoredirect
        connect to console:i:$ConnectToConsole
        remoteapplicationcmdline:s:$RemoteApplicationCmdline
        remoteapplicationexpandcmdline:i:$(if ($RemoteApplicationExpandcmdline) { 1 } else { 0 })
        remoteapplicationexpandworkingdir:i:$(if ($RemoteApplicationExpandworkingdir) { 1 } else { 0 })
        remoteapplicationfile:s:$RemoteApplicationFile
        remoteapplicationicon:s:$RemoteApplicationIcon
        remoteapplicationname:s:$RemoteApplicationName
        remoteapplicationprogram:s:$RemoteApplicationProgram
        $AdditionalArguments
        " | Out-File C:\temp\$Name.rdp

        mstsc C:\temp\$Name.rdp
        (Get-Process -Name mstsc | Select-Object -First 1).WaitForInputIdle() | Out-Null

        Add-Type -AssemblyName Microsoft.VisualBasic
        $success = $false

        while ($success -ne $true) {
        try {
            [Microsoft.VisualBasic.Interaction]::AppActivate("Windows-Sicherheit")
            $success = $true
        }
        catch {
            Start-Sleep 1
        }
        }

        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("$($Password -replace ".","{`$0}"){Enter}")

        Remove-Item C:\temp\$Name.rdp
    }
}
