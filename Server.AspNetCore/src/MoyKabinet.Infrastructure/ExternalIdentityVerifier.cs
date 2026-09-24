using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using MoyKabinet.Application;

namespace MoyKabinet.Infrastructure;

public sealed class ExternalIdentityVerifier(IHttpClientFactory clients, IConfiguration config) : IExternalIdentityVerifier
{
    private static readonly ConfigurationManager<OpenIdConnectConfiguration> GoogleMetadata = new(
        "https://accounts.google.com/.well-known/openid-configuration", new OpenIdConnectConfigurationRetriever());
    private static readonly ConfigurationManager<OpenIdConnectConfiguration> AppleMetadata = new(
        "https://appleid.apple.com/.well-known/openid-configuration", new OpenIdConnectConfigurationRetriever());

    public bool IsConfigured(string provider) => provider switch
    {
        "google" => Has("Auth:Google:ClientId") && Has("Auth:Google:RedirectUris"),
        "yandex" => Has("Auth:Yandex:ClientId") && Has("Auth:Yandex:RedirectUris"),
        "apple" => Has("Auth:Apple:ClientId") && Has("Auth:Apple:TeamId") && Has("Auth:Apple:KeyId") && Has("Auth:Apple:PrivateKey"),
        _ => false
    };

    public async Task<ExternalIdentity> ExchangeCodeAsync(ExternalExchangeRequest request, CancellationToken ct)
    {
        if (request.Code.Length is < 1 or > 4096 || request.CodeVerifier.Length is < 43 or > 128 ||
            request.CodeVerifier.Any(c => !(char.IsAsciiLetterOrDigit(c) || ".~-_".Contains(c))) || request.RedirectURI.Length > 2048)
            throw new AppProblem(400, "Некорректные данные входа.");
        return request.Provider switch
        {
            "google" => await GoogleAsync(request, ct),
            "yandex" => await YandexAsync(request, ct),
            _ => throw new AppProblem(400, "Неизвестный сервис входа.")
        };
    }

    public async Task<ExternalIdentity> ExchangeAppleAsync(AppleExchangeRequest request, CancellationToken ct)
    {
        if (request.IdentityToken.Length is < 1 or > 32_768 || request.AuthorizationCode.Length is < 1 or > 32_768 || request.UserIdentifier.Length is < 1 or > 512)
            throw new AppProblem(400, "Некорректные данные Apple ID.");
        EnsureConfigured("apple");
        var clientId = config["Auth:Apple:ClientId"]!;
        var identityToken = DecodeBase64(request.IdentityToken);
        var authorizationCode = DecodeBase64(request.AuthorizationCode);
        var first = await ValidateAsync(identityToken, await AppleMetadata.GetConfigurationAsync(ct), clientId, "https://appleid.apple.com");
        if (first.FindFirstValue("sub") != request.UserIdentifier) throw new AppProblem(401, "Apple ID не совпадает с подтверждённым входом.");
        var response = await PostForm("https://appleid.apple.com/auth/token", new()
        {
            ["grant_type"] = "authorization_code", ["code"] = authorizationCode,
            ["client_id"] = clientId, ["client_secret"] = AppleClientSecret()
        }, ct);
        var exchanged = response.RootElement.GetProperty("id_token").GetString() ?? throw new AppProblem(401, "Apple не подтвердил вход.");
        var second = await ValidateAsync(exchanged, await AppleMetadata.GetConfigurationAsync(ct), clientId, "https://appleid.apple.com");
        if (second.FindFirstValue("sub") != request.UserIdentifier) throw new AppProblem(401, "Apple ID не совпадает с подтверждённым входом.");
        var email = first.FindFirstValue("email");
        var refreshToken = response.RootElement.TryGetProperty("refresh_token", out var refresh) ? refresh.GetString() : null;
        return new("apple", request.UserIdentifier, email, request.DisplayName, null, refreshToken);
    }

    public async Task RevokeAsync(string provider, string refreshToken, CancellationToken ct)
    {
        if (provider != "apple") return;
        EnsureConfigured("apple");
        using var response = await clients.CreateClient("oauth").PostAsync("https://appleid.apple.com/auth/revoke",
            new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = config["Auth:Apple:ClientId"]!, ["client_secret"] = AppleClientSecret(),
                ["token"] = refreshToken, ["token_type_hint"] = "refresh_token"
            }), ct);
        if (!response.IsSuccessStatusCode) throw new AppProblem(502, "Apple временно не подтвердил удаление. Повторите позже.");
    }

    private async Task<ExternalIdentity> GoogleAsync(ExternalExchangeRequest request, CancellationToken ct)
    {
        EnsureConfigured("google"); ValidateRedirect("google", request.RedirectURI);
        var clientId = config["Auth:Google:ClientId"]!;
        var form = new Dictionary<string, string> { ["grant_type"]="authorization_code", ["code"]=request.Code, ["client_id"]=clientId, ["code_verifier"]=request.CodeVerifier, ["redirect_uri"]=request.RedirectURI };
        if (config["Auth:Google:ClientSecret"] is { Length: > 0 } secret) form["client_secret"] = secret;
        var tokens = await PostForm("https://oauth2.googleapis.com/token", form, ct);
        var idToken = tokens.RootElement.GetProperty("id_token").GetString() ?? throw new AppProblem(401, "Google не подтвердил вход.");
        var principal = await ValidateAsync(idToken, await GoogleMetadata.GetConfigurationAsync(ct), clientId, "https://accounts.google.com");
        var verified = string.Equals(principal.FindFirstValue("email_verified"), "true", StringComparison.OrdinalIgnoreCase);
        return new("google", principal.FindFirstValue("sub")!, verified ? principal.FindFirstValue("email") : null,
            principal.FindFirstValue("name"), Uri.TryCreate(principal.FindFirstValue("picture"), UriKind.Absolute, out var avatar) ? avatar : null);
    }

    private async Task<ExternalIdentity> YandexAsync(ExternalExchangeRequest request, CancellationToken ct)
    {
        EnsureConfigured("yandex"); ValidateRedirect("yandex", request.RedirectURI);
        var clientId = config["Auth:Yandex:ClientId"]!;
        var form = new Dictionary<string, string> { ["grant_type"]="authorization_code", ["code"]=request.Code, ["client_id"]=clientId, ["code_verifier"]=request.CodeVerifier };
        if (config["Auth:Yandex:ClientSecret"] is { Length: > 0 } secret) form["client_secret"] = secret;
        var tokens = await PostForm("https://oauth.yandex.ru/token", form, ct);
        var access = tokens.RootElement.GetProperty("access_token").GetString() ?? throw new AppProblem(401, "Яндекс не подтвердил вход.");
        using var message = new HttpRequestMessage(HttpMethod.Get, "https://login.yandex.ru/info?format=json");
        message.Headers.Authorization = new("OAuth", access);
        using var response = await clients.CreateClient("oauth").SendAsync(message, ct);
        if (!response.IsSuccessStatusCode) throw new AppProblem(401, "Яндекс не подтвердил вход.");
        using var info = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(ct));
        if (info.RootElement.GetProperty("client_id").GetString() != clientId) throw new AppProblem(401, "Токен выдан другому приложению.");
        var subject = info.RootElement.TryGetProperty("id", out var id) ? id.GetString() : info.RootElement.GetProperty("psuid").GetString();
        return new("yandex", subject ?? throw new AppProblem(401, "Яндекс не подтвердил пользователя."),
            Optional(info.RootElement, "default_email"), Optional(info.RootElement, "real_name") ?? Optional(info.RootElement, "display_name"), null);
    }

    private async Task<ClaimsPrincipal> ValidateAsync(string token, OpenIdConnectConfiguration metadata, string audience, string issuer)
    {
        try
        {
            var result = await new JwtSecurityTokenHandler().ValidateTokenAsync(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey=true, IssuerSigningKeys=metadata.SigningKeys, ValidateIssuer=true, ValidIssuer=issuer,
                ValidateAudience=true, ValidAudience=audience, ValidateLifetime=true, ClockSkew=TimeSpan.FromMinutes(2)
            });
            if (!result.IsValid) throw result.Exception ?? new SecurityTokenException();
            return new ClaimsPrincipal(result.ClaimsIdentity);
        }
        catch { throw new AppProblem(401, "Токен входа не прошёл проверку."); }
    }

    private async Task<JsonDocument> PostForm(string url, Dictionary<string,string> fields, CancellationToken ct)
    {
        using var response = await clients.CreateClient("oauth").PostAsync(url, new FormUrlEncodedContent(fields), ct);
        if (!response.IsSuccessStatusCode) throw new AppProblem(401, "Сервис не подтвердил вход.");
        return await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
    }

    private string AppleClientSecret()
    {
        using var key = ECDsa.Create();
        key.ImportFromPem(config["Auth:Apple:PrivateKey"]!.Replace("\\n", "\n"));
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken("" + config["Auth:Apple:TeamId"], "https://appleid.apple.com",
            [new Claim("sub", config["Auth:Apple:ClientId"]!)], now, now.AddMinutes(5),
            new SigningCredentials(new ECDsaSecurityKey(key) { KeyId = config["Auth:Apple:KeyId"] }, SecurityAlgorithms.EcdsaSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private void ValidateRedirect(string provider, string value)
    {
        var allowed = (config[$"Auth:{char.ToUpperInvariant(provider[0]) + provider[1..]}:RedirectUris"] ?? "").Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (!allowed.Contains(value, StringComparer.Ordinal)) throw new AppProblem(400, "Адрес возврата не разрешён.");
        if (requestVerifierInvalid(value)) throw new AppProblem(400, "Некорректный адрес возврата.");
        static bool requestVerifierInvalid(string uri) => !Uri.TryCreate(uri, UriKind.Absolute, out _);
    }
    private void EnsureConfigured(string provider) { if (!IsConfigured(provider)) throw new AppProblem(501, "Вход через этот сервис пока не настроен."); }
    private bool Has(string key) => !string.IsNullOrWhiteSpace(config[key]);
    private static string DecodeBase64(string value) { try { return Encoding.UTF8.GetString(Convert.FromBase64String(value)); } catch { throw new AppProblem(400, "Некорректные данные Apple ID."); } }
    private static string? Optional(JsonElement value, string name) => value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString() : null;
}
