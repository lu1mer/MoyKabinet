using System.Text.Json;
using System.Text.RegularExpressions;
using MoyKabinet.Application;

namespace MoyKabinet.Infrastructure;

public sealed partial class CabinetStateValidator : ICabinetStateValidator
{
    public JsonDocument ParseAndValidate(JsonElement state)
    {
        if (state.ValueKind != JsonValueKind.Object) throw Bad("Некорректные данные кабинета.");
        RequireArray(state, "clients", 50_000);
        RequireArray(state, "services", 1_000);
        RequireArray(state, "appointments", 200_000);
        if (!state.TryGetProperty("profile", out var profile) || profile.ValueKind != JsonValueKind.Object) throw Bad("Проверьте профиль.");
        var name = Text(profile, "name", 1, 200);
        _ = name;
        var opening = Int(profile, "openingHour", 0, 23);
        var closing = Int(profile, "closingHour", 1, 24);
        if (opening >= closing) throw Bad("Проверьте рабочие часы.");
        var clientIds = Ids(state.GetProperty("clients"));
        var serviceIds = Ids(state.GetProperty("services"));
        _ = serviceIds;
        foreach (var client in state.GetProperty("clients").EnumerateArray())
        {
            Text(client, "name", 1, 200); Text(client, "phone", 0, 100, optional: true); Text(client, "notes", 0, 10_000, optional: true);
            if (client.TryGetProperty("photos", out var photos) && (photos.ValueKind != JsonValueKind.Array || photos.GetArrayLength() > 8)) throw Bad("Слишком много фотографий.");
        }
        foreach (var service in state.GetProperty("services").EnumerateArray())
        {
            Text(service, "name", 1, 200); Int(service, "minutes", 15, 480); Int(service, "price", 0, 1_000_000);
        }
        foreach (var visit in state.GetProperty("appointments").EnumerateArray())
        {
            var client = Text(visit, "clientID", 1, 64);
            if (!Guid.TryParse(client, out var parsed) || !clientIds.Contains(parsed)) throw Bad("Запись ссылается на неизвестного клиента.");
            Text(visit, "serviceName", 1, 200); Int(visit, "minutes", 15, 480); Int(visit, "price", 0, 1_000_000);
            if (!visit.TryGetProperty("start", out var start) || start.ValueKind != JsonValueKind.Number || !start.TryGetDouble(out var seconds) || !double.IsFinite(seconds)) throw Bad("Некорректная дата.");
        }
        return JsonDocument.Parse(state.GetRawText(), new JsonDocumentOptions { MaxDepth = 64 });
    }

    private static HashSet<Guid> Ids(JsonElement array)
    {
        var result = new HashSet<Guid>();
        foreach (var item in array.EnumerateArray())
        {
            var id = Text(item, "id", 1, 64);
            if (!Guid.TryParse(id, out var value) || !result.Add(value)) throw Bad("Повторяющийся или некорректный идентификатор.");
        }
        return result;
    }
    private static void RequireArray(JsonElement root, string name, int maximum)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > maximum) throw Bad("Некорректная структура данных.");
    }
    private static string Text(JsonElement root, string name, int minimum, int maximum, bool optional = false)
    {
        if (!root.TryGetProperty(name, out var value)) { if (optional) return ""; throw Bad("Некорректное поле."); }
        if (value.ValueKind != JsonValueKind.String) throw Bad("Некорректное поле.");
        var text = value.GetString()?.Trim() ?? "";
        if (text.Length < minimum || text.Length > maximum) throw Bad("Некорректное поле.");
        return text;
    }
    private static int Int(JsonElement root, string name, int minimum, int maximum)
    {
        if (!root.TryGetProperty(name, out var value) || !value.TryGetInt32(out var number) || number < minimum || number > maximum) throw Bad("Некорректное число.");
        return number;
    }
    private static AppProblem Bad(string message) => new(400, message);
}
