using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using ReasonableLivePlayer.Automation;
using ReasonableLivePlayer.Models;
using ReasonableLivePlayer.Services;

namespace ReasonableLivePlayer.Views;

public partial class SettingsDialog : Window
{
    public SettingsDialog()
    {
        AvaloniaXamlLoader.Load(this);

        var deviceCombo = this.FindControl<ComboBox>("DeviceCombo")!;
        var channelCombo = this.FindControl<ComboBox>("ChannelCombo")!;
        var noteCombo = this.FindControl<ComboBox>("NoteCombo")!;
        var delayBox = this.FindControl<TextBox>("DelayTextBox")!;
        var spacingBox = this.FindControl<TextBox>("SpacingTextBox")!;
        var fontSizeBox = this.FindControl<TextBox>("FontSizeTextBox")!;
        var loadLastCheck = this.FindControl<CheckBox>("LoadLastPlaylistCheck")!;
        var alwaysOnTopCheck = this.FindControl<CheckBox>("AlwaysOnTopCheck")!;

        var devices = MidiNoteListener.GetAvailableDevices();
        deviceCombo.ItemsSource = devices;
        channelCombo.ItemsSource = Enumerable.Range(1, 16).ToList();
        noteCombo.ItemsSource = Enumerable.Range(0, 128).ToList();

        var settings = SettingsStore.Load();
        if (settings.MidiDeviceName != null && devices.Contains(settings.MidiDeviceName))
            deviceCombo.SelectedItem = settings.MidiDeviceName;
        channelCombo.SelectedItem = settings.MidiChannel;
        noteCombo.SelectedItem = settings.EndNoteNumber;
        delayBox.Text = settings.TransitionDelaySec.ToString();
        spacingBox.Text = settings.SongSpacing.ToString();
        fontSizeBox.Text = settings.SongFontSize.ToString();
        loadLastCheck.IsChecked = settings.LoadLastPlaylist;
        alwaysOnTopCheck.IsChecked = settings.AlwaysOnTop;

        // Accessibility permission check (macOS only)
        var accessLabel = this.FindControl<TextBlock>("AccessibilityStatus")!;
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            bool trusted = AXIsProcessTrusted();
            accessLabel.Text = trusted ? "✓ Granted" : "✕ Not granted — enable in System Settings → Privacy → Accessibility";
            accessLabel.Foreground = trusted ? Brushes.LimeGreen : Brushes.Orange;
        }
        else
        {
            accessLabel.Text = "N/A";
            accessLabel.Foreground = Brushes.Gray;
        }

        // MIDI connection status
        var midiLabel = this.FindControl<TextBlock>("MidiStatus")!;
        bool midiConnected = false;
        if (!string.IsNullOrEmpty(settings.MidiDeviceName) && devices.Contains(settings.MidiDeviceName))
        {
            // Check if we can connect to the selected device
            var testListener = new MidiNoteListener();
            midiConnected = testListener.Connect(settings.MidiDeviceName, settings.MidiChannel - 1, settings.EndNoteNumber);
            testListener.Dispose();
        }
        midiLabel.Text = midiConnected ? "✓ Connected" : "✕ Not connected";
        midiLabel.Foreground = midiConnected ? Brushes.LimeGreen : Brushes.Orange;
    }

    [DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")]
    private static extern bool AXIsProcessTrusted();

    private async void Save_Click(object? sender, RoutedEventArgs e)
    {
        var delayBox = this.FindControl<TextBox>("DelayTextBox")!;
        if (!int.TryParse(delayBox.Text, out int delay) || delay < 0 || delay > 99)
        {
            var msg = new MessageDialog("Transition delay must be a number between 0 and 99.",
                "Validation Error", ["OK"]);
            await msg.ShowDialog(this);
            delayBox.Focus();
            return;
        }

        var spacingBox = this.FindControl<TextBox>("SpacingTextBox")!;
        if (!int.TryParse(spacingBox.Text, out int spacing) || spacing < 0 || spacing > 20)
        {
            var msg = new MessageDialog("Song spacing must be a number between 0 and 20.",
                "Validation Error", ["OK"]);
            await msg.ShowDialog(this);
            spacingBox.Focus();
            return;
        }

        var fontSizeBox = this.FindControl<TextBox>("FontSizeTextBox")!;
        if (!double.TryParse(fontSizeBox.Text, out double fontSize) || fontSize < 10 || fontSize > 24)
        {
            var msg = new MessageDialog("Font size must be a number between 10 and 24.",
                "Validation Error", ["OK"]);
            await msg.ShowDialog(this);
            fontSizeBox.Focus();
            return;
        }

        var deviceCombo = this.FindControl<ComboBox>("DeviceCombo")!;
        var channelCombo = this.FindControl<ComboBox>("ChannelCombo")!;
        var noteCombo = this.FindControl<ComboBox>("NoteCombo")!;
        var loadLastCheck = this.FindControl<CheckBox>("LoadLastPlaylistCheck")!;
        var alwaysOnTopCheck = this.FindControl<CheckBox>("AlwaysOnTopCheck")!;

        var data = new SettingsData(
            deviceCombo.SelectedItem as string,
            channelCombo.SelectedItem is int ch ? ch : 1,
            noteCombo.SelectedItem is int note ? note : 0,
            delay,
            LastPlaylistPath: SettingsStore.Load().LastPlaylistPath,
            LoadLastPlaylist: loadLastCheck.IsChecked == true,
            AlwaysOnTop: alwaysOnTopCheck.IsChecked == true,
            SongSpacing: spacing,
            SongFontSize: fontSize
        );
        SettingsStore.Save(data);
        Close(true);
    }

    private void Cancel_Click(object? sender, RoutedEventArgs e) => Close(false);
}
