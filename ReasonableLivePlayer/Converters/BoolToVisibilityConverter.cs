using System.Globalization;
using Avalonia.Data.Converters;

namespace ReasonableLivePlayer.Converters;

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type t, object? p, CultureInfo c)
        => value is true;

    public object ConvertBack(object? value, Type t, object? p, CultureInfo c)
        => value is true;
}
