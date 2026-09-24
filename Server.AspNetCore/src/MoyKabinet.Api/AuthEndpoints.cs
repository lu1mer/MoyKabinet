using MoyKabinet.Application;
using Microsoft.AspNetCore.Mvc;

namespace MoyKabinet.Api;

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/auth").WithMetadata(new RequestSizeLimitAttribute(16_384));
        group.MapGet("/config", (IExternalIdentityVerifier external) => Results.Ok(new
        { email = true, apple = external.IsConfigured("apple"), google = external.IsConfigured("google"), yandex = external.IsConfigured("yandex") }));
        group.MapPost("/register", async (RegisterRequest request, IAuthService auth, CancellationToken ct) => Results.Ok(await auth.RegisterAsync(request, ct))).RequireRateLimiting("auth");
        group.MapPost("/confirm", async (ConfirmEmailRequest request, IAuthService auth, CancellationToken ct) => Results.Ok(await auth.ConfirmAsync(request, ct))).RequireRateLimiting("auth");
        group.MapPost("/login", async (LoginRequest request, IAuthService auth, CancellationToken ct) => Results.Ok(await auth.LoginAsync(request, ct))).RequireRateLimiting("auth");
        group.MapPost("/refresh", async (RefreshRequest request, IAuthService auth, CancellationToken ct) => Results.Ok(await auth.RefreshAsync(request, ct))).RequireRateLimiting("auth");
        group.MapPost("/password/reset/request", async (PasswordResetRequest request, IAuthService auth, CancellationToken ct) => { await auth.RequestPasswordResetAsync(request, ct); return Results.Accepted(); }).RequireRateLimiting("auth");
        group.MapPost("/password/reset/confirm", async (PasswordResetConfirmRequest request, IAuthService auth, CancellationToken ct) => { await auth.ResetPasswordAsync(request, ct); return Results.Ok(new { reset = true }); }).RequireRateLimiting("auth");
        group.MapPost("/exchange", async (ExternalExchangeRequest request, IExternalIdentityVerifier external, IAuthService auth, CancellationToken ct) =>
            Results.Ok(await auth.ExternalAsync(await external.ExchangeCodeAsync(request, ct), request.DeviceName, ct))).RequireRateLimiting("auth");
        group.MapPost("/apple", async (AppleExchangeRequest request, IExternalIdentityVerifier external, IAuthService auth, CancellationToken ct) =>
            Results.Ok(await auth.ExternalAsync(await external.ExchangeAppleAsync(request, ct), request.DeviceName, ct))).RequireRateLimiting("auth");
        group.MapGet("/me", async (HttpContext context, IAuthService auth, CancellationToken ct) => Results.Ok(new { user = await auth.RequireUserAsync(context.Request.Headers.Authorization, ct) }));
        group.MapPost("/logout", async (HttpContext context, IAuthService auth, CancellationToken ct) => { await auth.LogoutAsync(context.Request.Headers.Authorization, ct); return Results.Ok(new { revoked = true }); });
        group.MapDelete("/me", async (HttpContext context, IAuthService auth, CancellationToken ct) => { await auth.DeleteAsync(context.Request.Headers.Authorization, ct); return Results.Ok(new { deleted = true }); });
        return app;
    }
}
