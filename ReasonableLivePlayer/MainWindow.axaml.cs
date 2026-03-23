using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Data.Converters;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.VisualTree;
using ReasonableLivePlayer.Models;
using ReasonableLivePlayer.ViewModels;

namespace ReasonableLivePlayer;

public partial class MainWindow : Window
{
    private Song? _dragSong;
    private bool _isDragging;
    private Point _dragStart;

    public MainWindow()
    {
        AvaloniaXamlLoader.Load(this);
        var vm = new MainViewModel();
        DataContext = vm;
        Closing += MainWindow_Closing;

        // Set up file drop handling
        AddHandler(DragDrop.DropEvent, OnDrop);
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
        DragDrop.SetAllowDrop(this, true);

        _ = vm.CheckAccessibilityAsync();
    }

    private async void MainWindow_Closing(object? sender, WindowClosingEventArgs e)
    {
        if (DataContext is not MainViewModel vm) return;
        e.Cancel = true;
        if (await vm.PromptSaveIfDirtyAsync())
        {
            vm.Cleanup();
            Closing -= MainWindow_Closing;
            Close();
        }
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        if (e.Data.Contains(DataFormats.Files))
            e.DragEffects = DragDropEffects.Copy;
    }

    private void OnDrop(object? sender, DragEventArgs e)
    {
        if (DataContext is not MainViewModel vm) return;
        if (!e.Data.Contains(DataFormats.Files)) return;

        var files = e.Data.GetFiles();
        if (files == null) return;

        foreach (var item in files)
        {
            if (item is not IStorageFile file) continue;
            var path = file.TryGetLocalPath();
            if (path == null) continue;
            var ext = System.IO.Path.GetExtension(path).ToLowerInvariant();
            if (ext is ".reason" or ".rns")
                vm.Songs.Add(new Song { FilePath = path });
        }
    }

    // --- Drag-reorder handlers ---

    private void DragHandle_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (sender is not Control { DataContext: Song song }) return;
        _dragSong = song;
        _isDragging = false;
        _dragStart = e.GetPosition(this);
        e.Pointer.Capture((IInputElement)sender);
        e.Handled = true;
    }

    private void DragHandle_PointerMoved(object? sender, PointerEventArgs e)
    {
        if (_dragSong == null) return;
        var pos = e.GetPosition(this);
        var d = pos - _dragStart;
        if (!_isDragging && Math.Sqrt(d.X * d.X + d.Y * d.Y) > 5)
            _isDragging = true;

        if (_isDragging)
        {
            var listBox = this.FindControl<ListBox>("PlaylistBox")!;
            var indicator = this.FindControl<Controls.DropIndicatorAdorner>("DropIndicator")!;
            var lbPos = e.GetPosition(listBox);
            int idx = GetDropIndex(listBox, lbPos);
            var container = listBox.ContainerFromIndex(idx);
            if (container != null)
            {
                var cp = container.TranslatePoint(new Point(0, 0), listBox);
                if (cp != null)
                {
                    // Show line at top of target item (or bottom if dragging down)
                    var vm = (MainViewModel)DataContext!;
                    int srcIdx = vm.Songs.IndexOf(_dragSong);
                    double y = idx > srcIdx ? cp.Value.Y + container.Bounds.Height : cp.Value.Y;
                    var listBoxInParent = listBox.TranslatePoint(new Point(0, 0), indicator.Parent as Visual ?? listBox) ?? new Point(0, 0);
                    indicator.LineY = y + listBoxInParent.Y;
                    indicator.IsVisible = true;
                    indicator.InvalidateVisual();
                }
            }
        }
        e.Handled = true;
    }

    private void DragHandle_PointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        this.FindControl<Controls.DropIndicatorAdorner>("DropIndicator")!.IsVisible = false;

        if (_dragSong == null || DataContext is not MainViewModel vm)
        {
            _dragSong = null;
            return;
        }

        if (_isDragging)
        {
            var listBox = this.FindControl<ListBox>("PlaylistBox")!;
            var pos = e.GetPosition(listBox);
            int targetIndex = GetDropIndex(listBox, pos);
            int srcIndex = vm.Songs.IndexOf(_dragSong);
            if (srcIndex >= 0 && targetIndex >= 0 && targetIndex != srcIndex)
                vm.Songs.Move(srcIndex, targetIndex);
        }

        _dragSong = null;
        _isDragging = false;
        e.Handled = true;
    }

    private static int GetDropIndex(ListBox listBox, Point pos)
    {
        // Find which item the pointer is over based on Y position
        var panel = listBox.GetVisualDescendants().OfType<StackPanel>().FirstOrDefault()
                    ?? (Visual)listBox;
        int count = listBox.ItemCount;
        if (count == 0) return 0;

        for (int i = 0; i < count; i++)
        {
            var container = listBox.ContainerFromIndex(i);
            if (container == null) continue;
            var bounds = container.Bounds;
            var containerPos = container.TranslatePoint(new Point(0, 0), listBox);
            if (containerPos == null) continue;
            double midY = containerPos.Value.Y + bounds.Height / 2;
            if (pos.Y < midY) return i;
        }
        return count - 1;
    }
}

/// <summary>
/// Converts MidiConnected bool to red/green ellipse fill.
/// </summary>
public class MidiDotConverter : IValueConverter
{
    private static ISolidColorBrush? _green, _red;

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true
            ? (_green ??= new SolidColorBrush(Colors.LimeGreen))
            : (_red ??= new SolidColorBrush(Colors.Red));

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
