using System.IO;
using FsCheck;
using FsCheck.Xunit;
using Xunit;
using ReasonableLivePlayer.Models;
using ReasonableLivePlayer.Services;

namespace ReasonableLivePlayer.Tests;

/// <summary>
/// Feature: remember-window-bounds
/// Validates that window position and size persist across save/load.
/// </summary>
public class WindowBoundsPersistenceTests
{
    /// <summary>
    /// For any window position (X, Y) and size (width, height), saving settings
    /// to disk and loading them back should preserve the window bounds exactly.
    /// </summary>
    [Property(MaxTest = 100)]
    public Property WindowBounds_RoundTrip_Preserves_Data()
    {
        return Prop.ForAll(
            Arb.From(
                from x in Gen.Choose(-2000, 4000)
                from y in Gen.Choose(-2000, 4000)
                from width in Gen.Choose(200, 4000)
                from height in Gen.Choose(200, 4000)
                select (x, y, width, height)
            ),
            bounds =>
            {
                var settings = new SettingsData(
                    MidiDeviceName: null,
                    MidiChannel: 1,
                    EndNoteNumber: 0,
                    TransitionDelaySec: 5,
                    WindowX: bounds.x,
                    WindowY: bounds.y,
                    WindowWidth: bounds.width,
                    WindowHeight: bounds.height);

                var tempPath = Path.Combine(Path.GetTempPath(), $"rlp_bounds_{Guid.NewGuid()}.json");
                try
                {
                    SettingsStore.SaveTo(settings, tempPath);
                    var loaded = SettingsStore.LoadFrom(tempPath);
                    return loaded.WindowX == bounds.x
                        && loaded.WindowY == bounds.y
                        && loaded.WindowWidth == bounds.width
                        && loaded.WindowHeight == bounds.height;
                }
                finally
                {
                    if (File.Exists(tempPath)) File.Delete(tempPath);
                }
            });
    }

    /// <summary>
    /// Settings saved by an older version (no window bounds) should load with
    /// null bounds rather than throwing — i.e. the feature is backward compatible.
    /// </summary>
    [Fact]
    public void Load_LegacySettings_Without_Bounds_Yields_Null()
    {
        var tempPath = Path.Combine(Path.GetTempPath(), $"rlp_legacy_{Guid.NewGuid()}.json");
        try
        {
            // Legacy JSON predating the window-bounds fields.
            File.WriteAllText(tempPath,
                "{\"MidiDeviceName\":\"IAC Driver\",\"MidiChannel\":1," +
                "\"EndNoteNumber\":0,\"TransitionDelaySec\":5}");

            var loaded = SettingsStore.LoadFrom(tempPath);

            Assert.Null(loaded.WindowX);
            Assert.Null(loaded.WindowY);
            Assert.Null(loaded.WindowWidth);
            Assert.Null(loaded.WindowHeight);
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
    }
}
