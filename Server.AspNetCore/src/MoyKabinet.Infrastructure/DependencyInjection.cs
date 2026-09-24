using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MoyKabinet.Application;

namespace MoyKabinet.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connection = configuration.GetConnectionString("Database") ?? "Data Source=data/moykabinet.db";
        services.AddDbContext<AppDbContext>(options => options.UseSqlite(connection));
        services.AddAuthentication();
        services.AddAuthorization();
        services.AddIdentityCore<AppUser>(options =>
        {
            options.User.RequireUniqueEmail = true;
            options.Password.RequiredLength = 10;
            options.Password.RequireDigit = true;
            options.Password.RequireLowercase = true;
            options.Password.RequireUppercase = true;
            options.Password.RequireNonAlphanumeric = true;
            options.Lockout.MaxFailedAccessAttempts = 5;
            options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
        }).AddSignInManager().AddEntityFrameworkStores<AppDbContext>().AddDefaultTokenProviders();
        services.AddHttpClient("oauth", client => client.Timeout = TimeSpan.FromSeconds(15))
            .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
        var keys = configuration["DataProtection:KeysPath"] ?? "data/keys";
        Directory.CreateDirectory(keys);
        services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(keys)).SetApplicationName("MoyKabinet");
        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<ISecretGenerator, SecretGenerator>();
        services.AddSingleton<ICabinetStateValidator, CabinetStateValidator>();
        services.AddScoped<IAccountMailer, AccountMailer>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddSingleton<IExternalIdentityVerifier, ExternalIdentityVerifier>();
        return services;
    }
}
