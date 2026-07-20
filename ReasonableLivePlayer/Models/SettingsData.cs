namespace ReasonableLivePlayer.Models;

public record SettingsData(
    string? MidiDeviceName,
    int MidiChannel,          // 1-16
    int EndNoteNumber,        // 0-127
    int TransitionDelaySec,   // seconds to wait between closing one song and opening the next
    string? LastPlaylistPath = null,
    bool LoadLastPlaylist = false,
    bool AlwaysOnTop = false,
    int SongSpacing = 0,      // vertical spacing between songs in playlist (0-20 pixels)
    double SongFontSize = 13  // font size for song names in playlist (10-24)
);
