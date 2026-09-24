using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using MoyKabinet.Domain;

namespace MoyKabinet.Infrastructure;

public sealed class AppUser : IdentityUser
{
    public string? DisplayName { get; set; }
    public string? ProfileEmail { get; set; }
    public string Provider { get; set; } = "email";
    public string? ExternalSubject { get; set; }
    public string? AvatarUrl { get; set; }
}

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : IdentityDbContext<AppUser>(options)
{
    public DbSet<Cabinet> Cabinets => Set<Cabinet>();
    public DbSet<AccountSession> Sessions => Set<AccountSession>();
    public DbSet<CabinetAccess> CabinetAccesses => Set<CabinetAccess>();
    public DbSet<CabinetDeviceKey> CabinetDeviceKeys => Set<CabinetDeviceKey>();
    public DbSet<EmailVerification> EmailVerifications => Set<EmailVerification>();
    public DbSet<ExternalCredential> ExternalCredentials => Set<ExternalCredential>();
    public DbSet<BookingReceipt> BookingReceipts => Set<BookingReceipt>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.Entity<AppUser>().HasIndex(x => new { x.Provider, x.ExternalSubject }).IsUnique();
        builder.Entity<Cabinet>().Property(x => x.Version).IsConcurrencyToken();
        builder.Entity<AccountSession>().HasIndex(x => x.AccessTokenHash).IsUnique();
        builder.Entity<AccountSession>().HasIndex(x => x.RefreshTokenHash).IsUnique();
        builder.Entity<AccountSession>().HasOne<AppUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<CabinetAccess>().HasKey(x => new { x.UserId, x.CabinetId });
        builder.Entity<CabinetAccess>().HasOne<AppUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<CabinetAccess>().HasOne<Cabinet>().WithMany().HasForeignKey(x => x.CabinetId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<CabinetDeviceKey>().HasIndex(x => x.KeyHash).IsUnique();
        builder.Entity<CabinetDeviceKey>().HasOne<Cabinet>().WithMany().HasForeignKey(x => x.CabinetId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<EmailVerification>().HasOne<AppUser>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<ExternalCredential>().HasKey(x => x.UserId);
        builder.Entity<ExternalCredential>().HasOne<AppUser>().WithOne().HasForeignKey<ExternalCredential>(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<BookingReceipt>().HasKey(x => new { x.CabinetId, x.RequestId });
        builder.Entity<BookingReceipt>().HasOne<Cabinet>().WithMany().HasForeignKey(x => x.CabinetId).OnDelete(DeleteBehavior.Cascade);
    }
}
