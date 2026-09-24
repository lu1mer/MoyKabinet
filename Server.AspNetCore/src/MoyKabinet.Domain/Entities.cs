namespace MoyKabinet.Domain;

public sealed class Cabinet
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string OwnerKeyHash { get; set; } = "";
    public string StateJson { get; set; } = "{}";
    public int Revision { get; set; } = 1;
    public Guid Version { get; set; } = Guid.NewGuid();
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class AccountSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string UserId { get; set; } = "";
    public string AccessTokenHash { get; set; } = "";
    public string RefreshTokenHash { get; set; } = "";
    public DateTime AccessExpiresAtUtc { get; set; }
    public DateTime RefreshExpiresAtUtc { get; set; }
    public DateTime? RevokedAtUtc { get; set; }
    public string DeviceName { get; set; } = "iPhone";
}

public sealed class CabinetAccess
{
    public string UserId { get; set; } = "";
    public string CabinetId { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class CabinetDeviceKey
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string CabinetId { get; set; } = "";
    public string KeyHash { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class EmailVerification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string UserId { get; set; } = "";
    public string CodeHash { get; set; } = "";
    public string Purpose { get; set; } = "email";
    public DateTime ExpiresAtUtc { get; set; }
    public int Attempts { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class ExternalCredential
{
    public string UserId { get; set; } = "";
    public string Provider { get; set; } = "";
    public string ProtectedRefreshToken { get; set; } = "";
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}

public sealed class BookingReceipt
{
    public string CabinetId { get; set; } = "";
    public string RequestId { get; set; } = "";
    public string RequestHash { get; set; } = "";
    public string ResponseJson { get; set; } = "{}";
}
