using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MoyKabinet.Application;
using MoyKabinet.Domain;
using MoyKabinet.Infrastructure;

namespace MoyKabinet.Api;

public static partial class CabinetEndpoints
{
    private const long AppleEpoch = 978_307_200;
    private const int MaxCabinetsPerAccount = 20;

    public static IEndpointRouteBuilder MapCabinetEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/cabinets", CreateCabinetAsync).RequireRateLimiting("write");
        app.MapGet("/api/cabinets/{id}/state", GetStateAsync);
        app.MapPut("/api/cabinets/{id}/state", UpdateStateAsync).RequireRateLimiting("write");
        app.MapDelete("/api/cabinets/{id}", DeleteCabinetAsync).RequireRateLimiting("write");
        app.MapPost("/api/auth/cabinets/link", LinkCabinetAsync).RequireRateLimiting("write");
        app.MapGet("/api/auth/cabinets", ListCabinetsAsync);
        app.MapPost("/api/auth/cabinets/{id}/key", IssueDeviceKeyAsync).RequireRateLimiting("write");
        app.MapGet("/api/public/{id}", PublicCabinetAsync).RequireRateLimiting("public");
        app.MapGet("/api/public/{id}/slots", SlotsAsync).RequireRateLimiting("public");
        app.MapPost("/api/public/{id}/book", BookAsync)
            .WithMetadata(new RequestSizeLimitAttribute(16_384))
            .RequireRateLimiting("public");
        return app;
    }

    private static async Task<IResult> CreateCabinetAsync(CreateCabinetRequest request, HttpContext context, AppDbContext db,
        IAuthService auth, ISecretGenerator secrets, ICabinetStateValidator validator, CancellationToken ct)
    {
        var user = await auth.RequireUserAsync(context.Request.Headers.Authorization, ct);
        if (await db.CabinetAccesses.CountAsync(x => x.UserId == user.Id, ct) >= MaxCabinetsPerAccount)
            throw new AppProblem(429, "Достигнут лимит кабинетов для аккаунта.");
        using var state = validator.ParseAndValidate(request.State);
        var ownerKey = secrets.Create();
        var cabinet = new Cabinet { OwnerKeyHash = secrets.Hash(ownerKey), StateJson = state.RootElement.GetRawText() };
        db.Cabinets.Add(cabinet);
        db.CabinetAccesses.Add(new CabinetAccess { UserId = user.Id, CabinetId = cabinet.Id });
        await db.SaveChangesAsync(ct);
        return Results.Created($"/api/cabinets/{cabinet.Id}/state", StateReply(cabinet, ownerKey));
    }

    private static async Task<IResult> GetStateAsync(string id, HttpContext context, AppDbContext db, ISecretGenerator secrets, CancellationToken ct)
    {
        var cabinet = await CabinetAsync(id, db, ct); RequireOwner(context, cabinet, db, secrets);
        return Results.Ok(StateReply(cabinet));
    }

    private static async Task<IResult> UpdateStateAsync(string id, UpdateCabinetRequest request, HttpContext context, AppDbContext db,
        ISecretGenerator secrets, ICabinetStateValidator validator, CancellationToken ct)
    {
        var cabinet = await CabinetAsync(id, db, ct); RequireOwner(context, cabinet, db, secrets);
        if (request.Revision != cabinet.Revision) throw new AppProblem(409, "Кабинет изменился. Повторите синхронизацию.");
        using var state = validator.ParseAndValidate(request.State);
        cabinet.StateJson = state.RootElement.GetRawText(); cabinet.Revision++; cabinet.Version = Guid.NewGuid(); cabinet.UpdatedAtUtc = DateTime.UtcNow;
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { throw new AppProblem(409, "Кабинет изменился. Повторите синхронизацию."); }
        return Results.Ok(StateReply(cabinet));
    }

    private static async Task<IResult> DeleteCabinetAsync(string id, HttpContext context, AppDbContext db, ISecretGenerator secrets, CancellationToken ct)
    {
        var cabinet = await CabinetAsync(id, db, ct); RequireOwner(context, cabinet, db, secrets);
        db.Cabinets.Remove(cabinet); await db.SaveChangesAsync(ct); return Results.Ok(new { deleted = true });
    }

    private static async Task<IResult> LinkCabinetAsync(LinkCabinetRequest request, HttpContext context, AppDbContext db,
        IAuthService auth, ISecretGenerator secrets, CancellationToken ct)
    {
        var user = await auth.RequireUserAsync(context.Request.Headers.Authorization, ct);
        var cabinet = await CabinetAsync(request.CabinetID, db, ct);
        if (!OwnerMatches(request.OwnerKey, cabinet, db, secrets)) throw new AppProblem(401, "Неверный ключ кабинета.");
        if (!await db.CabinetAccesses.AnyAsync(x => x.UserId == user.Id && x.CabinetId == cabinet.Id, ct))
        {
            if (await db.CabinetAccesses.CountAsync(x => x.UserId == user.Id, ct) >= MaxCabinetsPerAccount)
                throw new AppProblem(429, "Достигнут лимит кабинетов для аккаунта.");
            db.CabinetAccesses.Add(new CabinetAccess { UserId = user.Id, CabinetId = cabinet.Id });
            await db.SaveChangesAsync(ct);
        }
        return Results.Ok(new { linked = true });
    }

    private static async Task<IResult> ListCabinetsAsync(HttpContext context, AppDbContext db, IAuthService auth, CancellationToken ct)
    {
        var user = await auth.RequireUserAsync(context.Request.Headers.Authorization, ct);
        var cabinets = await (from access in db.CabinetAccesses where access.UserId == user.Id
                              join cabinet in db.Cabinets on access.CabinetId equals cabinet.Id
                              orderby access.CreatedAtUtc descending select cabinet).ToListAsync(ct);
        var result = cabinets.Select(c =>
        {
            using var state = JsonDocument.Parse(c.StateJson); var profile = state.RootElement.GetProperty("profile");
            return new CabinetDto(c.Id, profile.GetProperty("name").GetString() ?? "Кабинет",
                profile.TryGetProperty("specialty", out var specialty) ? specialty.GetString() : null, c.Revision);
        });
        return Results.Ok(new { cabinets = result });
    }

    private static async Task<IResult> IssueDeviceKeyAsync(string id, HttpContext context, AppDbContext db, IAuthService auth, ISecretGenerator secrets, CancellationToken ct)
    {
        var user = await auth.RequireUserAsync(context.Request.Headers.Authorization, ct);
        if (!await db.CabinetAccesses.AnyAsync(x => x.UserId == user.Id && x.CabinetId == id, ct)) throw new AppProblem(403, "Кабинет не привязан к аккаунту.");
        if (await db.CabinetDeviceKeys.CountAsync(x => x.CabinetId == id, ct) >= 50) throw new AppProblem(429, "Слишком много подключённых устройств.");
        var key = secrets.Create(); db.CabinetDeviceKeys.Add(new CabinetDeviceKey { CabinetId = id, KeyHash = secrets.Hash(key) }); await db.SaveChangesAsync(ct);
        return Results.Ok(new { id, ownerKey = key });
    }

    private static async Task<IResult> PublicCabinetAsync(string id, AppDbContext db, CancellationToken ct)
    {
        var cabinet = await CabinetAsync(id, db, ct); using var state = JsonDocument.Parse(cabinet.StateJson);
        var profile = state.RootElement.GetProperty("profile");
        var services = state.RootElement.GetProperty("services").EnumerateArray().Where(x => !Bool(x, "archived"))
            .Select(x => new { id = x.GetProperty("id").GetString(), name = x.GetProperty("name").GetString(), minutes = x.GetProperty("minutes").GetInt32(), price = x.GetProperty("price").GetInt32() });
        return Results.Ok(new { profile = new { name = profile.GetProperty("name").GetString(), specialty = Optional(profile, "specialty"), timezone = profile.GetProperty("timezone").GetString() }, services });
    }

    private static async Task<IResult> SlotsAsync(string id, string service, string date, AppDbContext db, CancellationToken ct)
    {
        var cabinet = await CabinetAsync(id, db, ct); using var state = JsonDocument.Parse(cabinet.StateJson);
        if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", out var day)) throw new AppProblem(400, "Некорректная дата.");
        var target = state.RootElement.GetProperty("services").EnumerateArray().FirstOrDefault(x => x.GetProperty("id").GetString()?.Equals(service, StringComparison.OrdinalIgnoreCase) == true && !Bool(x, "archived"));
        if (target.ValueKind == JsonValueKind.Undefined) throw new AppProblem(404, "Услуга не найдена.");
        var slots = BuildSlots(state.RootElement, day, target.GetProperty("minutes").GetInt32());
        return Results.Ok(new { slots });
    }

    private static async Task<IResult> BookAsync(string id, BookingRequest request, AppDbContext db, ICabinetStateValidator validator, CancellationToken ct)
    {
        if (!request.Consent || request.Name.Trim().Length is < 1 or > 200 || !PhoneRegex().IsMatch(request.Phone) || request.Phone.Count(char.IsDigit) < 7)
            throw new AppProblem(400, "Проверьте имя, телефон и согласие.");
        if (!Guid.TryParse(request.RequestID, out _)) throw new AppProblem(400, "Некорректный идентификатор запроса.");
        var cabinet = await CabinetAsync(id, db, ct);
        var requestHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(request))));
        var receipt = await db.BookingReceipts.FindAsync([id, request.RequestID], ct);
        if (receipt is not null)
        {
            if (receipt.RequestHash != requestHash) throw new AppProblem(409, "Запрос с таким идентификатором уже использован.");
            return Results.Ok(JsonDocument.Parse(receipt.ResponseJson).RootElement.Clone());
        }
        var root = JsonNode.Parse(cabinet.StateJson)?.AsObject() ?? throw new AppProblem(500, "Данные кабинета повреждены.");
        var service = root["services"]?.AsArray().Select(x => x?.AsObject()).FirstOrDefault(x =>
            x?["id"]?.GetValue<string>().Equals(request.ServiceID, StringComparison.OrdinalIgnoreCase) == true && !(x?["archived"]?.GetValue<bool>() ?? false))
            ?? throw new AppProblem(404, "Услуга не найдена.");
        var startUtc = DateTimeOffset.FromUnixTimeSeconds((long)Math.Floor(request.Start) + AppleEpoch);
        var profile = root["profile"]?.AsObject() ?? throw new AppProblem(500, "Профиль кабинета повреждён.");
        var zone = TimeZoneInfo.FindSystemTimeZoneById(profile["timezone"]!.GetValue<string>());
        var local = TimeZoneInfo.ConvertTime(startUtc, zone); var date = DateOnly.FromDateTime(local.DateTime);
        var allowed = BuildSlots(JsonDocument.Parse(cabinet.StateJson).RootElement, date, service["minutes"]!.GetValue<int>()).Any(x => Math.Abs(x.start - request.Start) < 0.5);
        if (!allowed) throw new AppProblem(409, "Это время уже занято. Выберите другое окно.");
        var clientId = Guid.NewGuid().ToString().ToUpperInvariant(); var appointmentId = Guid.NewGuid().ToString().ToUpperInvariant();
        root["clients"]!.AsArray().Add(new JsonObject { ["id"] = clientId, ["name"] = request.Name.Trim(), ["phone"] = request.Phone.Trim(), ["notes"] = "Онлайн-запись", ["archived"] = false, ["photos"] = new JsonArray() });
        root["appointments"]!.AsArray().Add(new JsonObject { ["id"] = appointmentId, ["clientID"] = clientId, ["serviceName"] = service["name"]!.GetValue<string>(),
            ["start"] = request.Start, ["minutes"] = service["minutes"]!.GetValue<int>(), ["price"] = service["price"]!.GetValue<int>(), ["status"] = "Запланировано", ["note"] = "Онлайн-запись" });
        using var valid = validator.ParseAndValidate(JsonDocument.Parse(root.ToJsonString()).RootElement);
        var response = new { id = appointmentId, serviceName = service["name"]!.GetValue<string>(), start = request.Start, minutes = service["minutes"]!.GetValue<int>(), price = service["price"]!.GetValue<int>(), timezone = zone.Id };
        cabinet.StateJson = valid.RootElement.GetRawText(); cabinet.Revision++; cabinet.Version = Guid.NewGuid(); cabinet.UpdatedAtUtc = DateTime.UtcNow;
        db.BookingReceipts.Add(new BookingReceipt { CabinetId = id, RequestId = request.RequestID, RequestHash = requestHash, ResponseJson = JsonSerializer.Serialize(response) });
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { throw new AppProblem(409, "Это время только что заняли. Выберите другое окно."); }
        catch (DbUpdateException) { throw new AppProblem(409, "Запись уже обработана или время занято."); }
        return Results.Created($"/api/public/{id}", response);
    }

    private static IEnumerable<Slot> BuildSlots(JsonElement state, DateOnly day, int minutes)
    {
        var profile = state.GetProperty("profile"); var zone = TimeZoneInfo.FindSystemTimeZoneById(profile.GetProperty("timezone").GetString()!);
        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, zone).DateTime);
        if (day < today || day > today.AddDays(60)) return [];
        var weekday = ((int)day.DayOfWeek) + 1;
        if (!profile.GetProperty("weekdays").EnumerateArray().Any(x => x.GetInt32() == weekday)) return [];
        var opening = profile.GetProperty("openingHour").GetInt32(); var closing = profile.GetProperty("closingHour").GetInt32();
        var visits = state.GetProperty("appointments").EnumerateArray().Where(x => Optional(x, "status") != "Отменено")
            .Select(x => (start: x.GetProperty("start").GetDouble(), end: x.GetProperty("start").GetDouble() + x.GetProperty("minutes").GetInt32() * 60d)).ToArray();
        var result = new List<Slot>(); var now = DateTimeOffset.UtcNow.AddHours(1);
        for (var minute = opening * 60; minute + minutes <= closing * 60; minute += 15)
        {
            var local = day.ToDateTime(TimeOnly.MinValue).AddMinutes(minute);
            var offset = zone.GetUtcOffset(local); var utc = new DateTimeOffset(local, offset).ToUniversalTime();
            var apple = utc.ToUnixTimeSeconds() - AppleEpoch; var end = apple + minutes * 60d;
            if (utc < now || visits.Any(x => apple < x.end && end > x.start)) continue;
            result.Add(new Slot((double)apple, local.ToString("HH:mm")));
        }
        return result;
    }

    private static async Task<Cabinet> CabinetAsync(string id, AppDbContext db, CancellationToken ct)
    {
        if (!CabinetIdRegex().IsMatch(id)) throw new AppProblem(400, "Некорректный кабинет.");
        return await db.Cabinets.SingleOrDefaultAsync(x => x.Id == id, ct) ?? throw new AppProblem(404, "Кабинет не найден.");
    }
    private static void RequireOwner(HttpContext context, Cabinet cabinet, AppDbContext db, ISecretGenerator secrets)
    {
        var header = context.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.Ordinal) || !OwnerMatches(header[7..], cabinet, db, secrets)) throw new AppProblem(401, "Неверный ключ доступа.");
    }
    private static bool OwnerMatches(string key, Cabinet cabinet, AppDbContext db, ISecretGenerator secrets) =>
        secrets.Matches(key, cabinet.OwnerKeyHash) || db.CabinetDeviceKeys.Any(x => x.CabinetId == cabinet.Id && x.KeyHash == secrets.Hash(key));
    private static object StateReply(Cabinet cabinet, string? ownerKey = null) => new { id = ownerKey is null ? null : cabinet.Id, ownerKey, revision = cabinet.Revision, state = JsonDocument.Parse(cabinet.StateJson).RootElement.Clone() };
    private static bool Bool(JsonElement value, string name) => value.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.True;
    private static string? Optional(JsonElement value, string name) => value.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;

    private sealed record CreateCabinetRequest(JsonElement State);
    private sealed record UpdateCabinetRequest(JsonElement State, int Revision);
    private sealed record LinkCabinetRequest(string CabinetID, string OwnerKey);
    private sealed record BookingRequest(string ServiceID, double Start, string Name, string Phone, bool Consent, string RequestID);
    private sealed record Slot(double start, string label);
    [GeneratedRegex("^[a-f0-9]{32}$", RegexOptions.CultureInvariant)] private static partial Regex CabinetIdRegex();
    [GeneratedRegex("^[+0-9() \\-]{7,30}$", RegexOptions.CultureInvariant)] private static partial Regex PhoneRegex();
}
