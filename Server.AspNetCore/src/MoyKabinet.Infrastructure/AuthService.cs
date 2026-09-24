using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using MoyKabinet.Application;
using MoyKabinet.Domain;

namespace MoyKabinet.Infrastructure;

public sealed class AuthService(
    AppDbContext db, UserManager<AppUser> users, SignInManager<AppUser> signIn,
    ISecretGenerator secrets, IClock clock, IAccountMailer mailer, IExternalIdentityVerifier external,
    IDataProtectionProvider protectionProvider) : IAuthService
{
    private readonly IDataProtector credentialProtector = protectionProvider.CreateProtector("MoyKabinet.ExternalCredentials.v1");
    public async Task<RegistrationResult> RegisterAsync(RegisterRequest request, CancellationToken ct)
    {
        ValidateEmailAndPassword(request.Email, request.Password);
        var email = request.Email.Trim().ToLowerInvariant();
        var display = request.DisplayName.Trim();
        if (display.Length is < 2 or > 100) throw new AppProblem(400, "Укажите имя от 2 до 100 символов.");
        if (await users.FindByEmailAsync(email) is not null) throw new AppProblem(409, "Аккаунт с таким email уже существует.");
        var user = new AppUser { UserName = email, Email = email, ProfileEmail = email, DisplayName = display, Provider = "email", EmailConfirmed = false };
        var result = await users.CreateAsync(user, request.Password);
        if (!result.Succeeded) throw IdentityProblem(result);
        var code = RandomNumberGenerator.GetInt32(100_000, 1_000_000).ToString();
        db.EmailVerifications.Add(new EmailVerification { UserId = user.Id, Purpose = "email", CodeHash = secrets.Hash(code), ExpiresAtUtc = clock.UtcNow.AddMinutes(10) });
        await db.SaveChangesAsync(ct);
        try { await mailer.SendVerificationCodeAsync(email, code, ct); }
        catch { await users.DeleteAsync(user); throw; }
        return new(true, null);
    }

    public async Task<AuthSessionDto> ConfirmAsync(ConfirmEmailRequest request, CancellationToken ct)
    {
        if (request.Email.Length > 320 || request.Code.Length != 6 || !request.Code.All(char.IsDigit)) throw new AppProblem(400, "Проверьте код подтверждения.");
        var user = await users.FindByEmailAsync(request.Email.Trim()) ?? throw new AppProblem(400, "Код неверный или истёк.");
        var verification = await db.EmailVerifications.Where(x => x.UserId == user.Id && x.Purpose == "email").OrderByDescending(x => x.CreatedAtUtc).FirstOrDefaultAsync(ct)
            ?? throw new AppProblem(400, "Код неверный или истёк.");
        verification.Attempts++;
        if (verification.ExpiresAtUtc <= clock.UtcNow || verification.Attempts > 5 || !secrets.Matches(request.Code.Trim(), verification.CodeHash))
        {
            await db.SaveChangesAsync(ct); throw new AppProblem(400, "Код неверный или истёк.");
        }
        user.EmailConfirmed = true;
        db.EmailVerifications.RemoveRange(db.EmailVerifications.Where(x => x.UserId == user.Id));
        await db.SaveChangesAsync(ct);
        return await IssueAsync(user, request.DeviceName, ct);
    }

    public async Task<AuthSessionDto> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        ValidateEmailAndPassword(request.Email, request.Password);
        var user = await users.FindByEmailAsync(request.Email.Trim());
        if (user is null) { await PasswordHasherWorkAsync(request.Password); throw new AppProblem(401, "Неверный email или пароль."); }
        var result = await signIn.CheckPasswordSignInAsync(user, request.Password, lockoutOnFailure: true);
        if (result.IsLockedOut) throw new AppProblem(429, "Слишком много попыток. Повторите через 15 минут.");
        if (!result.Succeeded) throw new AppProblem(401, "Неверный email или пароль.");
        if (!user.EmailConfirmed) throw new AppProblem(403, "Подтвердите email кодом из письма.");
        return await IssueAsync(user, request.DeviceName, ct);
    }

    public async Task<AuthSessionDto> RefreshAsync(RefreshRequest request, CancellationToken ct)
    {
        var hash = secrets.Hash(request.RefreshToken);
        var current = await db.Sessions.AsNoTracking().SingleOrDefaultAsync(x => x.RefreshTokenHash == hash, ct);
        if (current is null || current.RevokedAtUtc is not null || current.RefreshExpiresAtUtc <= clock.UtcNow) throw new AppProblem(401, "Сессия истекла. Войдите снова.");
        var revoked = await db.Sessions.Where(x => x.Id == current.Id && x.RevokedAtUtc == null && x.RefreshExpiresAtUtc > clock.UtcNow)
            .ExecuteUpdateAsync(update => update.SetProperty(x => x.RevokedAtUtc, clock.UtcNow), ct);
        if (revoked != 1) throw new AppProblem(401, "Сессия уже обновлена. Войдите снова.");
        var user = await users.FindByIdAsync(current.UserId) ?? throw new AppProblem(401, "Сессия истекла. Войдите снова.");
        return await IssueAsync(user, request.DeviceName ?? current.DeviceName, ct);
    }

    public async Task<AuthSessionDto> ExternalAsync(ExternalIdentity identity, string? deviceName, CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.Provider == identity.Provider && x.ExternalSubject == identity.Subject, ct);
        if (user is null)
        {
            var subjectKey = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity.Subject))).ToLowerInvariant();
            user = new AppUser { UserName = $"{identity.Provider}-{subjectKey}@external.local", Provider = identity.Provider, ExternalSubject = identity.Subject,
                ProfileEmail = identity.Email, DisplayName = identity.DisplayName, AvatarUrl = identity.AvatarUrl?.AbsoluteUri, EmailConfirmed = true };
            var created = await users.CreateAsync(user);
            if (!created.Succeeded) throw IdentityProblem(created);
        }
        else
        {
            user.ProfileEmail = identity.Email ?? user.ProfileEmail;
            user.DisplayName = identity.DisplayName ?? user.DisplayName;
            user.AvatarUrl = identity.AvatarUrl?.AbsoluteUri ?? user.AvatarUrl;
            await users.UpdateAsync(user);
        }
        if (!string.IsNullOrWhiteSpace(identity.ProviderRefreshToken))
        {
            var credential = await db.ExternalCredentials.SingleOrDefaultAsync(x => x.UserId == user.Id, ct);
            if (credential is null)
            {
                credential = new ExternalCredential { UserId = user.Id, Provider = identity.Provider };
                db.ExternalCredentials.Add(credential);
            }
            credential.ProtectedRefreshToken = credentialProtector.Protect(identity.ProviderRefreshToken);
            credential.UpdatedAtUtc = clock.UtcNow;
            await db.SaveChangesAsync(ct);
        }
        return await IssueAsync(user, deviceName, ct);
    }

    public async Task<AuthUserDto> RequireUserAsync(string? authorization, CancellationToken ct)
    {
        var (_, user) = await RequireSessionAsync(authorization, ct);
        return ToDto(user);
    }

    public async Task LogoutAsync(string? authorization, CancellationToken ct)
    {
        var (session, _) = await RequireSessionAsync(authorization, ct);
        session.RevokedAtUtc = clock.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(string? authorization, CancellationToken ct)
    {
        var (_, user) = await RequireSessionAsync(authorization, ct);
        var credential = await db.ExternalCredentials.SingleOrDefaultAsync(x => x.UserId == user.Id, ct);
        if (credential is not null)
        {
            string providerToken;
            try { providerToken = credentialProtector.Unprotect(credential.ProtectedRefreshToken); }
            catch { throw new AppProblem(500, "Не удалось прочитать данные отзыва внешнего входа."); }
            await external.RevokeAsync(credential.Provider, providerToken, ct);
        }
        var result = await users.DeleteAsync(user);
        if (!result.Succeeded) throw new AppProblem(500, "Не удалось удалить аккаунт.");
    }

    public async Task RequestPasswordResetAsync(PasswordResetRequest request, CancellationToken ct)
    {
        if (request.Email.Length is < 3 or > 320) throw new AppProblem(400, "Проверьте email.");
        var user = await users.FindByEmailAsync(request.Email.Trim());
        if (user is null || user.Provider != "email" || !user.EmailConfirmed) { await PasswordHasherWorkAsync(request.Email); return; }
        var old = db.EmailVerifications.Where(x => x.UserId == user.Id && x.Purpose == "reset");
        db.EmailVerifications.RemoveRange(old);
        var code = RandomNumberGenerator.GetInt32(100_000, 1_000_000).ToString();
        db.EmailVerifications.Add(new EmailVerification { UserId = user.Id, Purpose = "reset", CodeHash = secrets.Hash(code), ExpiresAtUtc = clock.UtcNow.AddMinutes(10) });
        await db.SaveChangesAsync(ct);
        await mailer.SendPasswordResetCodeAsync(user.Email!, code, ct);
    }

    public async Task ResetPasswordAsync(PasswordResetConfirmRequest request, CancellationToken ct)
    {
        ValidateEmailAndPassword(request.Email, request.NewPassword);
        if (request.Code.Length != 6 || !request.Code.All(char.IsDigit)) throw new AppProblem(400, "Проверьте код подтверждения.");
        var user = await users.FindByEmailAsync(request.Email.Trim()) ?? throw new AppProblem(400, "Код неверный или истёк.");
        var verification = await db.EmailVerifications.Where(x => x.UserId == user.Id && x.Purpose == "reset").OrderByDescending(x => x.CreatedAtUtc).FirstOrDefaultAsync(ct)
            ?? throw new AppProblem(400, "Код неверный или истёк.");
        verification.Attempts++;
        if (verification.ExpiresAtUtc <= clock.UtcNow || verification.Attempts > 5 || !secrets.Matches(request.Code.Trim(), verification.CodeHash))
        { await db.SaveChangesAsync(ct); throw new AppProblem(400, "Код неверный или истёк."); }
        var token = await users.GeneratePasswordResetTokenAsync(user);
        var result = await users.ResetPasswordAsync(user, token, request.NewPassword);
        if (!result.Succeeded) throw IdentityProblem(result);
        db.EmailVerifications.RemoveRange(db.EmailVerifications.Where(x => x.UserId == user.Id && x.Purpose == "reset"));
        foreach (var session in db.Sessions.Where(x => x.UserId == user.Id && x.RevokedAtUtc == null)) session.RevokedAtUtc = clock.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    private async Task<(AccountSession, AppUser)> RequireSessionAsync(string? authorization, CancellationToken ct)
    {
        if (authorization is null || !authorization.StartsWith("Bearer ", StringComparison.Ordinal) || authorization.Length > 600) throw new AppProblem(401, "Нужен вход в аккаунт.");
        var hash = secrets.Hash(authorization[7..]);
        var session = await db.Sessions.SingleOrDefaultAsync(x => x.AccessTokenHash == hash, ct);
        if (session is null || session.RevokedAtUtc is not null || session.AccessExpiresAtUtc <= clock.UtcNow) throw new AppProblem(401, "Сессия истекла. Войдите снова.");
        var user = await users.FindByIdAsync(session.UserId) ?? throw new AppProblem(401, "Сессия истекла. Войдите снова.");
        return (session, user);
    }

    private async Task<AuthSessionDto> IssueAsync(AppUser user, string? deviceName, CancellationToken ct)
    {
        var access = secrets.Create(); var refresh = secrets.Create(48); var expiry = clock.UtcNow.AddHours(1);
        db.Sessions.Add(new AccountSession { UserId = user.Id, AccessTokenHash = secrets.Hash(access), RefreshTokenHash = secrets.Hash(refresh),
            AccessExpiresAtUtc = expiry, RefreshExpiresAtUtc = clock.UtcNow.AddDays(90), DeviceName = string.IsNullOrWhiteSpace(deviceName) ? "iPhone" : deviceName.Trim()[..Math.Min(deviceName.Trim().Length, 100)] });
        await db.SaveChangesAsync(ct);
        return new(access, refresh, new DateTimeOffset(expiry).ToUnixTimeSeconds(), ToDto(user));
    }

    private static AuthUserDto ToDto(AppUser user) => new(user.Id, user.Provider, user.ProfileEmail ?? user.Email, user.DisplayName,
        Uri.TryCreate(user.AvatarUrl, UriKind.Absolute, out var avatar) ? avatar : null);
    private static AppProblem IdentityProblem(IdentityResult result) => new(400, string.Join(" ", result.Errors.Select(x => x.Code switch
    {
        "PasswordTooShort" => "Пароль слишком короткий.", "PasswordRequiresUpper" => "Добавьте заглавную букву.",
        "PasswordRequiresLower" => "Добавьте строчную букву.", "PasswordRequiresDigit" => "Добавьте цифру.",
        "PasswordRequiresNonAlphanumeric" => "Добавьте специальный символ.", "InvalidEmail" => "Проверьте email.",
        _ => "Проверьте данные регистрации."
    }).Distinct()));
    private static Task PasswordHasherWorkAsync(string password)
    {
        _ = new PasswordHasher<AppUser>().HashPassword(new AppUser(), password); return Task.CompletedTask;
    }
    private static void ValidateEmailAndPassword(string email, string password)
    {
        if (string.IsNullOrWhiteSpace(email) || email.Length > 320 || password.Length is < 1 or > 256)
            throw new AppProblem(400, "Проверьте email и пароль.");
    }
}
