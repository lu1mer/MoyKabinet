using System.Text.Json;

namespace MoyKabinet.Application;

public sealed record AuthUserDto(string Id, string Provider, string? Email, string? DisplayName, Uri? AvatarURL);
public sealed record AuthSessionDto(string AccessToken, string RefreshToken, long ExpiresAt, AuthUserDto User);
public sealed record RegisterRequest(string Email, string Password, string DisplayName, string? DeviceName);
public sealed record LoginRequest(string Email, string Password, string? DeviceName);
public sealed record ConfirmEmailRequest(string Email, string Code, string? DeviceName);
public sealed record RefreshRequest(string RefreshToken, string? DeviceName);
public sealed record PasswordResetRequest(string Email);
public sealed record PasswordResetConfirmRequest(string Email, string Code, string NewPassword);
public sealed record ExternalExchangeRequest(string Provider, string Code, string CodeVerifier, string RedirectURI, string? DeviceName);
public sealed record AppleExchangeRequest(string Provider, string IdentityToken, string AuthorizationCode, string UserIdentifier, string? Email, string? DisplayName, string? DeviceName);
public sealed record ExternalIdentity(string Provider, string Subject, string? Email, string? DisplayName, Uri? AvatarUrl, string? ProviderRefreshToken = null);
public sealed record CabinetDto(string Id, string Name, string? Specialty, int Revision);

public interface IClock { DateTime UtcNow { get; } }
public interface ISecretGenerator
{
    string Create(int bytes = 32);
    string Hash(string value);
    bool Matches(string value, string hash);
}
public interface IAccountMailer
{
    Task SendVerificationCodeAsync(string email, string code, CancellationToken cancellationToken);
    Task SendPasswordResetCodeAsync(string email, string code, CancellationToken cancellationToken);
}
public interface ICabinetStateValidator { JsonDocument ParseAndValidate(JsonElement state); }
public interface IExternalIdentityVerifier
{
    bool IsConfigured(string provider);
    Task<ExternalIdentity> ExchangeCodeAsync(ExternalExchangeRequest request, CancellationToken cancellationToken);
    Task<ExternalIdentity> ExchangeAppleAsync(AppleExchangeRequest request, CancellationToken cancellationToken);
    Task RevokeAsync(string provider, string refreshToken, CancellationToken cancellationToken);
}
public sealed record RegistrationResult(bool VerificationRequired, AuthSessionDto? Session);
public interface IAuthService
{
    Task<RegistrationResult> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken);
    Task<AuthSessionDto> ConfirmAsync(ConfirmEmailRequest request, CancellationToken cancellationToken);
    Task<AuthSessionDto> LoginAsync(LoginRequest request, CancellationToken cancellationToken);
    Task<AuthSessionDto> RefreshAsync(RefreshRequest request, CancellationToken cancellationToken);
    Task<AuthSessionDto> ExternalAsync(ExternalIdentity identity, string? deviceName, CancellationToken cancellationToken);
    Task<AuthUserDto> RequireUserAsync(string? authorization, CancellationToken cancellationToken);
    Task LogoutAsync(string? authorization, CancellationToken cancellationToken);
    Task DeleteAsync(string? authorization, CancellationToken cancellationToken);
    Task RequestPasswordResetAsync(PasswordResetRequest request, CancellationToken cancellationToken);
    Task ResetPasswordAsync(PasswordResetConfirmRequest request, CancellationToken cancellationToken);
}

public sealed class AppProblem(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}
