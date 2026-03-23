using Commons.Music.Midi;

namespace ReasonableLivePlayer.Automation;

/// <summary>
/// Cross-platform MIDI input listener using managed-midi.
/// Listens for a specific note-on message matching a configured channel and note number.
/// </summary>
public class MidiNoteListener : IDisposable
{
    private IMidiInput? _input;

    public string? DeviceName { get; private set; }
    public int Channel { get; private set; }     // 0-15
    public int NoteNumber { get; private set; }  // 0-127
    public bool IsConnected { get; private set; }

    public event Action? EndNoteReceived;
    public event Action<bool>? ConnectionChanged;

    public bool Connect(string deviceName, int channel, int noteNumber)
    {
        Disconnect();
        DeviceName = deviceName;
        Channel = channel;
        NoteNumber = noteNumber;

        try
        {
            var access = MidiAccessManager.Default;
            var port = access.Inputs.FirstOrDefault(p =>
                string.Equals(p.Name, deviceName, StringComparison.OrdinalIgnoreCase));
            if (port == null)
            {
                IsConnected = false;
                ConnectionChanged?.Invoke(false);
                return false;
            }

            _input = access.OpenInputAsync(port.Id).Result;
            _input.MessageReceived += OnMidiMessage;
            IsConnected = true;
            ConnectionChanged?.Invoke(true);
            return true;
        }
        catch
        {
            IsConnected = false;
            ConnectionChanged?.Invoke(false);
            return false;
        }
    }

    public void Disconnect()
    {
        if (_input != null)
        {
            _input.MessageReceived -= OnMidiMessage;
            _input.CloseAsync().Wait();
            _input = null;
        }
        if (IsConnected)
        {
            IsConnected = false;
            ConnectionChanged?.Invoke(false);
        }
    }

    private void OnMidiMessage(object? sender, MidiReceivedEventArgs e)
    {
        // Parse raw MIDI bytes
        if (e.Length < 3) return;
        int status = e.Data[e.Start];
        int note = e.Data[e.Start + 1];
        int velocity = e.Data[e.Start + 2];

        int midiData = status | (note << 8) | (velocity << 16);
        if (IsMatchingNoteOn(midiData, Channel, NoteNumber))
            EndNoteReceived?.Invoke();
    }

    /// <summary>
    /// Determines if a raw MIDI message matches the configured channel and note
    /// with non-zero velocity. Extracted for testability.
    /// </summary>
    public static bool IsMatchingNoteOn(int midiData, int channel, int noteNumber)
    {
        int status = midiData & 0xFF;
        int note = (midiData >> 8) & 0x7F;
        int velocity = (midiData >> 16) & 0x7F;

        int messageType = status & 0xF0;
        int messageChannel = status & 0x0F;

        return messageType == 0x90
            && messageChannel == channel
            && note == noteNumber
            && velocity > 0;
    }

    public static List<string> GetAvailableDevices()
    {
        try
        {
            var access = MidiAccessManager.Default;
            return access.Inputs.Select(p => p.Name).ToList();
        }
        catch
        {
            return [];
        }
    }

    public void Dispose()
    {
        Disconnect();
        GC.SuppressFinalize(this);
    }

    ~MidiNoteListener() => Disconnect();
}
