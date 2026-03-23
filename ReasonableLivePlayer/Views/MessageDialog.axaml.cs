using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace ReasonableLivePlayer.Views;

public partial class MessageDialog : Window
{
    public string Message { get; }

    public MessageDialog(string message, string title, string[] buttons)
    {
        Message = message;
        Title = title;
        DataContext = this;
        AvaloniaXamlLoader.Load(this);

        var panel = this.FindControl<StackPanel>("ButtonPanel")!;
        foreach (var label in buttons)
        {
            var btn = new Button { Content = label, Width = 80, Height = 28 };
            var captured = label;
            btn.Click += (_, _) => Close(captured);
            panel.Children.Add(btn);
        }
    }

    public MessageDialog() : this("", "", []) { }
}
