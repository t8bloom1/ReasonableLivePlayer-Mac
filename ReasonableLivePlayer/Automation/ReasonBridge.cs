using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace ReasonableLivePlayer.Automation;

/// <summary>
/// Cross-platform bridge for opening/closing Reason song files.
/// Uses shell-execute on all platforms; uses AppleScript on macOS for closing,
/// process kill on Linux, and falls back to process tracking.
/// </summary>
public class ReasonBridge
{
    private readonly Dictionary<string, Process?> _openProcesses = new(StringComparer.OrdinalIgnoreCase);

    public async Task OpenSongAsync(string filePath)
    {
        var psi = new ProcessStartInfo
        {
            FileName = RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "open" : filePath,
            UseShellExecute = true
        };
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            psi.Arguments = $"\"{filePath}\"";

        var proc = Process.Start(psi);
        _openProcesses[filePath] = proc;

        // Wait briefly for the app to launch
        await Task.Delay(500);
    }

    public async Task CloseSongAsync(string filePath)
    {
        var songName = Path.GetFileNameWithoutExtension(filePath);

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            // Use AppleScript to close the specific document window in Reason
            try
            {
                var script = "tell application \"Reason\" to activate\n" +
                             "delay 0.3\n" +
                             "tell application \"System Events\"\n" +
                             "  tell process \"Reason\"\n" +
                             "    click menu item \"Close\" of menu \"File\" of menu bar 1\n" +
                             "  end tell\n" +
                             "end tell";
                var p = Process.Start(new ProcessStartInfo("osascript", "-")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true
                });
                if (p != null)
                {
                    await p.StandardInput.WriteAsync(script);
                    p.StandardInput.Close();
                }
            }
            catch { /* Best effort */ }
        }
        else
        {
            // Fallback: kill the tracked process
            if (_openProcesses.TryGetValue(filePath, out var proc) && proc is { HasExited: false })
            {
                try { proc.Kill(); } catch { }
            }
        }

        _openProcesses.Remove(filePath);
    }
}
