using System.Collections.Concurrent;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MoyKabinet.Application;
using MoyKabinet.Infrastructure;

namespace MoyKabinet.Api.Tests;

public sealed class FakeMailer : IAccountMailer
{
    public ConcurrentDictionary<string, string> Codes { get; } = new();
    public Task SendVerificationCodeAsync(string email, string code, CancellationToken cancellationToken)
    { Codes[email] = code; return Task.CompletedTask; }
    public Task SendPasswordResetCodeAsync(string email, string code, CancellationToken cancellationToken)
    { Codes[email] = code; return Task.CompletedTask; }
}

public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public FakeMailer Mailer { get; } = new();
    private readonly string database = Path.Combine(Path.GetTempPath(), $"moykabinet-{Guid.NewGuid():N}.db");
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<AppDbContext>();
            services.AddDbContext<AppDbContext>(options => options.UseSqlite($"Data Source={database}"));
            services.RemoveAll<IAccountMailer>();
            services.AddSingleton<IAccountMailer>(Mailer);
        });
    }
    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing && File.Exists(database)) File.Delete(database);
    }
}
