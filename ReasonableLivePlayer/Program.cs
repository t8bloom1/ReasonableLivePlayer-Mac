using System;
using System.IO;
using Avalonia;

namespace ReasonableLivePlayer;

class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception ex)
        {
            var log = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
                "rlp-crash.txt");
            try { File.WriteAllText(log, ex.ToString()); } catch { }
            throw;
        }
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
