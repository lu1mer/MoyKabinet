using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace MoyKabinet.Api.Tests;

public sealed class AuthAndSyncTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private readonly HttpClient client = factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });

    [Fact]
    public async Task RegistrationConfirmationRefreshAndLogoutAreRealSessions()
    {
        var email = $"master-{Guid.NewGuid():N}@example.test";
        var register = await client.PostAsJsonAsync("/api/auth/register", new { email, password = "Strong!Pass9", displayName = "Анна", deviceName = "Tests" });
        Assert.Equal(HttpStatusCode.OK, register.StatusCode);
        Assert.True((await register.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("verificationRequired").GetBoolean());
        var code = factory.Mailer.Codes[email];
        var confirm = await client.PostAsJsonAsync("/api/auth/confirm", new { email, code, deviceName = "Tests" });
        confirm.EnsureSuccessStatusCode();
        var first = await confirm.Content.ReadFromJsonAsync<JsonElement>();
        var access = first.GetProperty("accessToken").GetString()!;
        var refresh = first.GetProperty("refreshToken").GetString()!;
        using var me = new HttpRequestMessage(HttpMethod.Get, "/api/auth/me"); me.Headers.Authorization = new("Bearer", access);
        Assert.Equal(email, (await (await client.SendAsync(me)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("user").GetProperty("email").GetString());
        var refreshed = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = refresh, deviceName = "Tests" });
        refreshed.EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = refresh, deviceName = "Replay" })).StatusCode);
        var renewed = (await refreshed.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString()!;
        using var logout = new HttpRequestMessage(HttpMethod.Post, "/api/auth/logout") { Content = JsonContent.Create(new { }) }; logout.Headers.Authorization = new("Bearer", renewed);
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(logout)).StatusCode);
        using var rejected = new HttpRequestMessage(HttpMethod.Get, "/api/auth/me"); rejected.Headers.Authorization = new("Bearer", renewed);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.SendAsync(rejected)).StatusCode);
    }

    [Fact]
    public async Task AuthenticatedCabinetPersistsAndUsesOptimisticRevision()
    {
        var token = await RegisterAsync();
        using var create = new HttpRequestMessage(HttpMethod.Post, "/api/cabinets") { Content = JsonContent.Create(new { state = State() }) };
        create.Headers.Authorization = new("Bearer", token);
        var createdResponse = await client.SendAsync(create); Assert.Equal(HttpStatusCode.Created, createdResponse.StatusCode);
        var created = await createdResponse.Content.ReadFromJsonAsync<JsonElement>();
        var id = created.GetProperty("id").GetString()!; var owner = created.GetProperty("ownerKey").GetString()!;
        using var get = new HttpRequestMessage(HttpMethod.Get, $"/api/cabinets/{id}/state"); get.Headers.Authorization = new("Bearer", owner);
        Assert.Equal(1, (await (await client.SendAsync(get)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt32());
        using var update = new HttpRequestMessage(HttpMethod.Put, $"/api/cabinets/{id}/state") { Content = JsonContent.Create(new { state = State("Новый кабинет"), revision = 1 }) }; update.Headers.Authorization = new("Bearer", owner);
        Assert.Equal(2, (await (await client.SendAsync(update)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt32());
        using var stale = new HttpRequestMessage(HttpMethod.Put, $"/api/cabinets/{id}/state") { Content = JsonContent.Create(new { state = State(), revision = 1 }) }; stale.Headers.Authorization = new("Bearer", owner);
        Assert.Equal(HttpStatusCode.Conflict, (await client.SendAsync(stale)).StatusCode);
        using var list = new HttpRequestMessage(HttpMethod.Get, "/api/auth/cabinets"); list.Headers.Authorization = new("Bearer", token);
        Assert.Equal("Новый кабинет", (await (await client.SendAsync(list)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("cabinets")[0].GetProperty("name").GetString());
    }

    [Fact]
    public async Task WrongPasswordLocksOutAndPrivateApiRejectsAnonymous()
    {
        var email = $"lock-{Guid.NewGuid():N}@example.test"; await RegisterAsync(email);
        for (var attempt = 0; attempt < 4; attempt++)
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/auth/login", new { email, password = "Wrong!Pass9" })).StatusCode);
        Assert.Equal((HttpStatusCode)429, (await client.PostAsJsonAsync("/api/auth/login", new { email, password = "Wrong!Pass9" })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/cabinets", new { state = State() })).StatusCode);
    }

    [Fact]
    public async Task AccountDeletionRevokesEveryLocalSession()
    {
        var token = await RegisterAsync();
        using var delete = new HttpRequestMessage(HttpMethod.Delete, "/api/auth/me"); delete.Headers.Authorization = new("Bearer", token);
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(delete)).StatusCode);
        using var me = new HttpRequestMessage(HttpMethod.Get, "/api/auth/me"); me.Headers.Authorization = new("Bearer", token);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.SendAsync(me)).StatusCode);
    }

    [Fact]
    public async Task ApiResponsesDisableCachingAndSendSecurityHeaders()
    {
        var response = await client.GetAsync("/api/auth/config");
        response.EnsureSuccessStatusCode();
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
        Assert.Contains("nosniff", response.Headers.GetValues("X-Content-Type-Options"));
        Assert.Contains("camera=(), microphone=(), geolocation=()", response.Headers.GetValues("Permissions-Policy"));
        Assert.Contains("frame-ancestors 'none'", response.Headers.GetValues("Content-Security-Policy").Single());
    }

    [Fact]
    public async Task AccountCannotCreateMoreThanTwentyCabinets()
    {
        var token = await RegisterAsync();
        for (var index = 0; index < 20; index++)
        {
            using var create = new HttpRequestMessage(HttpMethod.Post, "/api/cabinets") { Content = JsonContent.Create(new { state = State($"Кабинет {index}") }) };
            create.Headers.Authorization = new("Bearer", token);
            Assert.Equal(HttpStatusCode.Created, (await client.SendAsync(create)).StatusCode);
        }
        using var rejected = new HttpRequestMessage(HttpMethod.Post, "/api/cabinets") { Content = JsonContent.Create(new { state = State("Лишний кабинет") }) };
        rejected.Headers.Authorization = new("Bearer", token);
        Assert.Equal((HttpStatusCode)429, (await client.SendAsync(rejected)).StatusCode);
    }

    [Fact]
    public async Task PasswordRecoveryChangesPasswordAndRevokesSessions()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.test"; var oldAccess = await RegisterAsync(email);
        Assert.Equal(HttpStatusCode.Accepted, (await client.PostAsJsonAsync("/api/auth/password/reset/request", new { email })).StatusCode);
        var reset = await client.PostAsJsonAsync("/api/auth/password/reset/confirm", new { email, code = factory.Mailer.Codes[email], newPassword = "New!Strong9Pass" });
        Assert.Equal(HttpStatusCode.OK, reset.StatusCode);
        using var old = new HttpRequestMessage(HttpMethod.Get, "/api/auth/me"); old.Headers.Authorization = new("Bearer", oldAccess);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.SendAsync(old)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/auth/login", new { email, password = "New!Strong9Pass", deviceName = "Tests" })).StatusCode);
    }

    [Fact]
    public async Task PublicBookingIsAtomicAndIdempotent()
    {
        var token = await RegisterAsync(); var serviceId = Guid.NewGuid();
        using var create = new HttpRequestMessage(HttpMethod.Post, "/api/cabinets") { Content = JsonContent.Create(new { state = State(serviceId: serviceId) }) };
        create.Headers.Authorization = new("Bearer", token);
        var created = await (await client.SendAsync(create)).Content.ReadFromJsonAsync<JsonElement>();
        var id = created.GetProperty("id").GetString()!; var owner = created.GetProperty("ownerKey").GetString()!;
        var date = DateTime.UtcNow.AddDays(2).ToString("yyyy-MM-dd");
        var slots = await client.GetFromJsonAsync<JsonElement>($"/api/public/{id}/slots?service={serviceId}&date={date}");
        var start = slots.GetProperty("slots")[0].GetProperty("start").GetDouble(); var requestId = Guid.NewGuid();
        var payload = new { serviceID = serviceId, start, name = "Клиент", phone = "+7 999 000-00-00", consent = true, requestID = requestId };
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync($"/api/public/{id}/book", payload)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync($"/api/public/{id}/book", payload)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync($"/api/public/{id}/book", new { serviceID = serviceId, start, name = "Другой", phone = "+7 999 000-00-00", consent = true, requestID = requestId })).StatusCode);
        using var stateRequest = new HttpRequestMessage(HttpMethod.Get, $"/api/cabinets/{id}/state"); stateRequest.Headers.Authorization = new("Bearer", owner);
        Assert.Single((await (await client.SendAsync(stateRequest)).Content.ReadFromJsonAsync<JsonElement>()).GetProperty("state").GetProperty("appointments").EnumerateArray());
    }

    private async Task<string> RegisterAsync(string? selectedEmail = null)
    {
        var email = selectedEmail ?? $"cabinet-{Guid.NewGuid():N}@example.test";
        (await client.PostAsJsonAsync("/api/auth/register", new { email, password = "Strong!Pass9", displayName = "Мастер", deviceName = "Tests" })).EnsureSuccessStatusCode();
        var response = await client.PostAsJsonAsync("/api/auth/confirm", new { email, code = factory.Mailer.Codes[email], deviceName = "Tests" });
        response.EnsureSuccessStatusCode(); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString()!;
    }

    private static object State(string name = "Кабинет", Guid? serviceId = null) => new
    {
        schemaVersion = 2, clients = Array.Empty<object>(), appointments = Array.Empty<object>(),
        services = new[] { new { id = serviceId ?? Guid.NewGuid(), name = "Маникюр", minutes = 60, price = 2500, archived = false } },
        profile = new { name, specialty = "Мастер", openingHour = 9, closingHour = 19, weekdays = new[] { 1,2,3,4,5,6,7 }, timezone = "Europe/Moscow", reminders = false }
    };
}
