using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using ReasonableLivePlayer.Automation;
using ReasonableLivePlayer.Models;
using ReasonableLivePlayer.Services;
using ReasonableLivePlayer.Views;

namespace ReasonableLivePlayer.ViewModels;

public class MainViewModel : INotifyPropertyChanged
{
    private readonly ReasonBridge _bridge = new();
    private readonly MidiNoteListener _midiListener = new();
    private bool _accessibilityGranted;
    private int _currentIndex = -1;
    private bool _isPlaylistActive;
    private bool _midiConnected;
    private bool _alwaysOnTop;
    private string _statusText = "Ready";
    private int _transitionDelaySec = 5;
    private bool _playlistDirty;

    public ObservableCollection<Song> Songs { get; } = [];

    public bool IsPlaylistActive
    {
        get => _isPlaylistActive;
        set { _isPlaylistActive = value; OnPropertyChanged(); OnPropertyChanged(nameof(PlayPauseLabel)); OnPropertyChanged(nameof(PlayPauseTooltip)); SelectSongCommand?.RaiseCanExecuteChanged(); }
    }

    public string PlayPauseLabel => IsPlaylistActive ? "⏸" : "▶";
    public string PlayPauseTooltip => IsPlaylistActive ? "Pause" : "Play";
    public string StatusText { get => _statusText; set { _statusText = value; OnPropertyChanged(); } }

    public bool MidiConnected
    {
        get => _midiConnected;
        set { _midiConnected = value; OnPropertyChanged(); OnPropertyChanged(nameof(MidiStatusText)); }
    }
    public string MidiStatusText => MidiConnected ? "MIDI connected" : "MIDI not connected";

    public bool AlwaysOnTop
    {
        get => _alwaysOnTop;
        set { _alwaysOnTop = value; OnPropertyChanged(); }
    }

    public bool PlaylistDirty
    {
        get => _playlistDirty;
        set { _playlistDirty = value; OnPropertyChanged(); }
    }

    public RelayCommand AddSongsCommand { get; }
    public RelayCommand RemoveSongCommand { get; }
    public RelayCommand PlayPauseCommand { get; }
    public RelayCommand SkipCommand { get; }
    public RelayCommand MoveUpCommand { get; }
    public RelayCommand MoveDownCommand { get; }
    public RelayCommand OpenSettingsCommand { get; }
    public RelayCommand SavePlaylistCommand { get; }
    public RelayCommand LoadPlaylistCommand { get; }
    public RelayCommand OpenHelpCommand { get; }
    public RelayCommand SelectSongCommand { get; }

    public MainViewModel()
    {
        _midiListener.EndNoteReceived += OnEndNoteReceived;
        _midiListener.ConnectionChanged += connected =>
            Dispatcher.UIThread.Post(() => MidiConnected = connected);

        Songs.CollectionChanged += (_, _) =>
        {
            PlaylistDirty = true;
            PlayPauseCommand?.RaiseCanExecuteChanged();
            SkipCommand?.RaiseCanExecuteChanged();
            SavePlaylistCommand?.RaiseCanExecuteChanged();
        };

        var settings = SettingsStore.Load();
        _transitionDelaySec = settings.TransitionDelaySec;
        AlwaysOnTop = settings.AlwaysOnTop;

        if (!string.IsNullOrEmpty(settings.MidiDeviceName))
            _midiListener.Connect(settings.MidiDeviceName, settings.MidiChannel - 1, settings.EndNoteNumber);

        if (settings.LoadLastPlaylist && !string.IsNullOrEmpty(settings.LastPlaylistPath)
            && System.IO.File.Exists(settings.LastPlaylistPath))
        {
            var paths = PlaylistFileService.Load(settings.LastPlaylistPath);
            foreach (var p in paths)
                Songs.Add(new Song { FilePath = p });
            StatusText = $"Loaded {Songs.Count} songs";
            PlaylistDirty = false;
        }

        AddSongsCommand = new RelayCommand(async _ =>
        {
            var window = GetMainWindow();
            if (window == null) return;
            var files = await window.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Add Songs",
                AllowMultiple = true,
                FileTypeFilter = [new FilePickerFileType("Reason Songs") { Patterns = ["*.reason", "*.rns"] }]
            });
            foreach (var f in files)
            {
                var path = f.TryGetLocalPath();
                if (path != null) Songs.Add(new Song { FilePath = path });
            }
        });

        RemoveSongCommand = new RelayCommand(p => { if (p is Song s) Songs.Remove(s); });

        PlayPauseCommand = new RelayCommand(_ =>
        {
            if (IsPlaylistActive) Pause();
            else Play();
        }, _ => Songs.Count > 0 && _accessibilityGranted);

        SkipCommand = new RelayCommand(_ => Skip(), _ => Songs.Count > 0);

        MoveUpCommand = new RelayCommand(p =>
        {
            if (p is Song s) { var i = Songs.IndexOf(s); if (i > 0) Songs.Move(i, i - 1); }
        });

        MoveDownCommand = new RelayCommand(p =>
        {
            if (p is Song s) { var i = Songs.IndexOf(s); if (i < Songs.Count - 1) Songs.Move(i, i + 1); }
        });

        OpenSettingsCommand = new RelayCommand(async _ =>
        {
            var window = GetMainWindow();
            if (window == null) return;
            var dlg = new SettingsDialog();
            var result = await dlg.ShowDialog<bool?>(window);
            if (result == true)
            {
                _midiListener.Disconnect();
                var s = SettingsStore.Load();
                _transitionDelaySec = s.TransitionDelaySec;
                AlwaysOnTop = s.AlwaysOnTop;
                if (!string.IsNullOrEmpty(s.MidiDeviceName))
                    _midiListener.Connect(s.MidiDeviceName, s.MidiChannel - 1, s.EndNoteNumber);
            }
        });

        SavePlaylistCommand = new RelayCommand(async _ => await SavePlaylist(), _ => Songs.Count > 0);

        LoadPlaylistCommand = new RelayCommand(async _ =>
        {
            var window = GetMainWindow();
            if (window == null) return;
            var files = await window.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Open Playlist",
                AllowMultiple = false,
                FileTypeFilter = [new FilePickerFileType("RLP Playlist") { Patterns = ["*.rlp"] }]
            });
            if (files.Count == 0) return;
            var path = files[0].TryGetLocalPath();
            if (path == null) return;

            var paths = PlaylistFileService.Load(path);
            Songs.Clear();
            _currentIndex = -1;
            IsPlaylistActive = false;
            foreach (var p in paths)
                Songs.Add(new Song { FilePath = p });
            StatusText = $"Loaded {Songs.Count} songs";
            PlaylistDirty = false;
            var cur = SettingsStore.Load();
            SettingsStore.Save(cur with { LastPlaylistPath = path });
        });

        OpenHelpCommand = new RelayCommand(async _ =>
        {
            var window = GetMainWindow();
            if (window == null) return;
            var dlg = new HelpDialog();
            await dlg.ShowDialog(window);
        });

        SelectSongCommand = new RelayCommand(p =>
        {
            if (p is Song s && !IsPlaylistActive)
            {
                var idx = Songs.IndexOf(s);
                if (idx >= 0)
                {
                    _currentIndex = idx;
                    SetActiveSong(idx);
                    StatusText = $"Next: {s.DisplayName}";
                }
            }
        }, _ => !IsPlaylistActive);
    }

    public async Task<bool> PromptSaveIfDirtyAsync()
    {
        if (!PlaylistDirty || Songs.Count == 0) return true;
        var window = GetMainWindow();
        if (window == null) return true;

        var box = new MessageDialog("The playlist has been modified. Save before closing?",
            "Save Playlist", ["Yes", "No", "Cancel"]);
        var result = await box.ShowDialog<string?>(window);

        if (result == "Cancel") return false;
        if (result == "Yes") await SavePlaylist();
        return true;
    }

    public void Cleanup() => _midiListener.Dispose();

    private async Task SavePlaylist()
    {
        var window = GetMainWindow();
        if (window == null) return;
        var file = await window.StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save Playlist",
            DefaultExtension = "rlp",
            FileTypeChoices = [new FilePickerFileType("RLP Playlist") { Patterns = ["*.rlp"] }]
        });
        if (file == null) return;
        var path = file.TryGetLocalPath();
        if (path == null) return;

        PlaylistFileService.Save(Songs.Select(s => s.FilePath).ToList(), path);
        PlaylistDirty = false;
        var cur = SettingsStore.Load();
        SettingsStore.Save(cur with { LastPlaylistPath = path });
    }

    private void OnEndNoteReceived()
    {
        Dispatcher.UIThread.Post(() =>
        {
            if (!IsPlaylistActive) return;
            AdvanceToNext();
        });
    }

    private async void Play()
    {
        if (Songs.Count == 0) return;
        if (_currentIndex < 0) _currentIndex = 0;
        SetActiveSong(_currentIndex);
        var song = Songs[_currentIndex];
        StatusText = $"Opening: {song.DisplayName}";
        await _bridge.OpenSongAsync(song.FilePath);
        IsPlaylistActive = true;
        StatusText = $"Playing: {song.DisplayName}";
    }

    private void Pause()
    {
        IsPlaylistActive = false;
        StatusText = "Paused";
    }

    private async void Skip()
    {
        bool wasPlaying = IsPlaylistActive;
        if (wasPlaying) await CloseCurrentAsync();
        IsPlaylistActive = false;

        if (_currentIndex < Songs.Count - 1)
        {
            _currentIndex++;
            SetActiveSong(_currentIndex);
            if (wasPlaying)
            {
                var song = Songs[_currentIndex];
                StatusText = $"Opening: {song.DisplayName}";
                await Task.Delay(_transitionDelaySec * 1000);
                await _bridge.OpenSongAsync(song.FilePath);
                IsPlaylistActive = true;
                StatusText = $"Ready: {song.DisplayName}";
            }
            else
            {
                StatusText = $"Skipped to: {Songs[_currentIndex].DisplayName}";
            }
        }
        else
        {
            ClearActiveSong();
            _currentIndex = -1;
            StatusText = "Set complete";
        }
    }

    private async void AdvanceToNext(bool alreadyClosed = false)
    {
        if (!alreadyClosed) await CloseCurrentAsync();

        if (_currentIndex < Songs.Count - 1)
        {
            _currentIndex++;
            SetActiveSong(_currentIndex);
            var song = Songs[_currentIndex];
            StatusText = $"Opening: {song.DisplayName}";
            await Task.Delay(_transitionDelaySec * 1000);
            await _bridge.OpenSongAsync(song.FilePath);
            StatusText = $"Ready: {song.DisplayName}";
        }
        else
        {
            ClearActiveSong();
            _currentIndex = -1;
            IsPlaylistActive = false;
            StatusText = "Set complete";
        }
    }

    private async Task CloseCurrentAsync()
    {
        if (_currentIndex >= 0 && _currentIndex < Songs.Count)
            await _bridge.CloseSongAsync(Songs[_currentIndex].FilePath);
    }

    private void SetActiveSong(int index)
    {
        foreach (var s in Songs) s.IsActive = false;
        if (index >= 0 && index < Songs.Count)
            Songs[index].IsActive = true;
    }

    private void ClearActiveSong()
    {
        foreach (var s in Songs) s.IsActive = false;
    }

    private static Window? GetMainWindow() =>
        (Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.MainWindow;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? n = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));

    // --- Accessibility permission (macOS) ---

    [DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")]
    private static extern bool AXIsProcessTrusted();

    public async Task CheckAccessibilityAsync()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            _accessibilityGranted = true;
            PlayPauseCommand?.RaiseCanExecuteChanged();
            return;
        }

        await Task.Delay(2000);

        if (AXIsProcessTrusted())
        {
            _accessibilityGranted = true;
            PlayPauseCommand?.RaiseCanExecuteChanged();
            return;
        }

        System.Diagnostics.Process.Start("open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
        StatusText = "⚠ Accessibility permission required — grant in System Settings, then restart";
    }
}
