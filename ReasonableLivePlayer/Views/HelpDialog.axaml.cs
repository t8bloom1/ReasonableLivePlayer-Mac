using System.Diagnostics;
using System.Reflection;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;

namespace ReasonableLivePlayer.Views;

public partial class HelpDialog : Window
{
    public HelpDialog()
    {
        AvaloniaXamlLoader.Load(this);

        var asm = Assembly.GetExecutingAssembly();
        var version = asm.GetName().Version;
        this.FindControl<TextBlock>("VersionText")!.Text = $"Version: {version?.Major}.{version?.Minor}.{version?.Build}";

        // Extract build date from InformationalVersion (set via SourceRevisionId)
        var infoVersion = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        string buildDate = "unknown";
        if (infoVersion != null)
        {
            // Format: "1.0.0+build2025-03-24" — extract date after "build"
            var plusIdx = infoVersion.IndexOf("+build", StringComparison.Ordinal);
            if (plusIdx >= 0)
                buildDate = infoVersion[(plusIdx + 6)..];
        }
        this.FindControl<TextBlock>("BuildDateText")!.Text = $"Build date: {buildDate}";
    }

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();

    private void RepoLink_Click(object? sender, PointerPressedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/t8bloom1/ReasonableLivePlayer-Mac")
            { UseShellExecute = true });
    }

    private void LicenseLink_Click(object? sender, PointerPressedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/t8bloom1/ReasonableLivePlayer-Mac/blob/main/LICENSE")
            { UseShellExecute = true });
    }
}
