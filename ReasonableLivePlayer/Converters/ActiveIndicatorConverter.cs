using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;

namespace ReasonableLivePlayer.Converters;

public class ActiveIndicatorConverter : IMultiValueConverter
{
    public object? Convert(IList<object?> values, Type targetType, object? parameter, CultureInfo culture)
    {
        if (values.Count < 2 || values[0] is not bool isActive)
            return "";
        return isActive ? "▶" : "";
    }
}

public class ActiveIndicatorColorConverter : IMultiValueConverter
{
    private static ISolidColorBrush? _green, _grey;

    public object? Convert(IList<object?> values, Type targetType, object? parameter, CultureInfo culture)
    {
        if (values.Count < 2 || values[0] is not bool isActive)
            return Brushes.Transparent;
        if (!isActive) return Brushes.Transparent;
        bool isPlaying = values[1] is true;
        return isPlaying
            ? (_green ??= new SolidColorBrush(Color.Parse("#00CC66")))
            : (_grey ??= new SolidColorBrush(Color.Parse("#999999")));
    }
}
