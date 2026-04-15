# Window Manager - List and move windows
# Usage:
#   .\window-manager.ps1 -List                              # List all windows
#   .\window-manager.ps1 -Title "Window Title" [-X 0] [-Y 0]  # Move by title
#   .\window-manager.ps1 -Handle 0x12AB34CD [-X 0] [-Y 0]     # Move by handle

[CmdletBinding(DefaultParameterSetName='ListParameterSet')]
param(
    [Parameter(ParameterSetName='ListParameterSet')]
    [switch]$List,

    [Parameter(Mandatory=$true, ParameterSetName='TitleParameterSet')]
    [string]$Title,

    [Parameter(Mandatory=$true, ParameterSetName='HandleParameterSet')]
    [string]$Handle,

    [int]$X = 0,
    [int]$Y = 0
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WindowManager {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static void ListAllWindows(Action<string, int, int, int, int, int> callback) {
        EnumWindows(new EnumWindowsProc((hWnd, lParam) => EnumWindowsCallback(hWnd, lParam, callback)), IntPtr.Zero);
    }

    private static bool EnumWindowsCallback(IntPtr hWnd, IntPtr lParam, Action<string, int, int, int, int, int> callback) {
        if (!IsWindowVisible(hWnd))
            return true;

        StringBuilder sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        string title = sb.ToString();

        if (!string.IsNullOrEmpty(title)) {
            RECT rect;
            GetWindowRect(hWnd, out rect);
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            callback(title, hWnd.ToInt32(), rect.Left, rect.Top, width, height);
        }

        return true;
    }
}
"@

# List all windows
if ($List -or $PSCmdlet.ParameterSetName -eq 'List') {
    $script:windows = @()

    $callback = {
        param($title, $handle, $left, $top, $width, $height)

        $obj = [PSCustomObject]@{
            Title  = $title
            Handle = "0x{0:X8}" -f $handle
            Left   = $left
            Top    = $top
            Width  = $width
            Height = $height
        }
        $script:windows += $obj
    }

    [WindowManager]::ListAllWindows($callback)
    $script:windows | Format-Table -AutoSize
}
# Move window
else {
    # Find the window
    if ($Handle) {
        # Convert hex string to IntPtr
        $hwnd = [IntPtr]([Convert]::ToInt32($Handle, 16))
    } elseif ($Title) {
        $hwnd = [WindowManager]::FindWindow($null, $Title)
    } else {
        Write-Host "Specify either -Title or -Handle" -ForegroundColor Red
        exit 1
    }

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Host "Window not found" -ForegroundColor Red
        exit 1
    }

    # Get current window dimensions
    $rect = New-Object WindowManager+RECT
    [WindowManager]::GetWindowRect($hwnd, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top

    # Move window to specified position
    $SWP_NOZORDER = 0x04
    $result = [WindowManager]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, $width, $height, $SWP_NOZORDER)

    if ($result) {
        Write-Host "Window moved to ($X,$Y) successfully" -ForegroundColor Green
    } else {
        Write-Host "Failed to move window" -ForegroundColor Red
    }
}
