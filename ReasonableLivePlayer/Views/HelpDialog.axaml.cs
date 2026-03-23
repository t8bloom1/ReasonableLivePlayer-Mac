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
        this.FindControl<TextBlock>("BuildDateText")!.Text = $"Build date: {DateTime.Now:yyyy-MM-dd}";
    }

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();

    private void RepoLink_Click(object? sender, PointerPressedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/t8bloom1/ReasonableLivePlayer")
            { UseShellExecute = true });
    }
}
