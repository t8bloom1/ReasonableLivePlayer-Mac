using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace ReasonableLivePlayer.Controls;

/// <summary>
/// A simple control that draws a horizontal line to indicate drop position.
/// Overlaid on the ListBox during drag operations.
/// </summary>
public class DropIndicatorAdorner : Control
{
    private IPen? _linePen;

    public double LineY { get; set; }

    public override void Render(DrawingContext context)
    {
        _linePen ??= new Pen(Brushes.White, 2);
        context.DrawLine(_linePen, new Point(0, LineY), new Point(Bounds.Width, LineY));
    }
}
