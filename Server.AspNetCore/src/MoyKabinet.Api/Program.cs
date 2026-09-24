using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.HttpOverrides;
using System.Net;
using MoyKabinet.Api;
using MoyKabinet.Application;
using MoyKabinet.Infrastructure;

// Resolve static booking assets both from a published application and from a
// source checkout started with `dotnet run`.
var webRoot = new[]
{
    Path.Combine(AppContext.BaseDirectory, "wwwroot"),
    Path.Combine(Directory.GetCurrentDirectory(), "wwwroot"),
    Path.Combine(Directory.GetCurrentDirectory(), "src", "MoyKabinet.Api", "wwwroot")
}.FirstOrDefault(path => File.Exists(Path.Combine(path, "index.html")));
var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    WebRootPath = webRoot
});
builder.Services.Configure<JsonOptions>(options => options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase);
builder.Services.AddProblemDetails();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddInfrastructure(builder.Configuration);
var testing = builder.Environment.IsEnvironment("Testing");
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 50_000_000);
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.ForwardLimit = 1;
    foreach (var value in builder.Configuration.GetSection("ReverseProxy:KnownProxies").Get<string[]>() ?? [])
        if (IPAddress.TryParse(value, out var address)) options.KnownProxies.Add(address);
});
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("auth", context => RateLimitPartition.GetSlidingWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new SlidingWindowRateLimiterOptions
        { PermitLimit = testing ? 1_000 : 20, Window = TimeSpan.FromMinutes(1), SegmentsPerWindow = 4, QueueLimit = 0 }));
    options.AddPolicy("public", context => RateLimitPartition.GetTokenBucketLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new TokenBucketRateLimiterOptions
        { TokenLimit = 60, TokensPerPeriod = 20, ReplenishmentPeriod = TimeSpan.FromMinutes(1), AutoReplenishment = true, QueueLimit = 0 }));
    options.AddPolicy("write", context => RateLimitPartition.GetSlidingWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new SlidingWindowRateLimiterOptions
        { PermitLimit = testing ? 1_000 : 60, Window = TimeSpan.FromMinutes(1), SegmentsPerWindow = 4, QueueLimit = 0 }));
});

var app = builder.Build();
app.UseForwardedHeaders();
if (!app.Environment.IsDevelopment() && !app.Environment.IsEnvironment("Testing")) app.UseHsts();
app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var exception = context.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var problem = exception as AppProblem;
    context.Response.StatusCode = problem?.Status ?? 500;
    await context.Response.WriteAsJsonAsync(new { error = problem?.Message ?? "Внутренняя ошибка сервера." });
}));
app.UseHttpsRedirection();
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "same-origin";
    context.Response.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";
    context.Response.Headers["Content-Security-Policy"] = app.Environment.IsDevelopment() && context.Request.Path.StartsWithSegments("/swagger")
        ? "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'"
        : "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'";
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        context.Response.Headers.CacheControl = "no-store";
        context.Response.Headers.Pragma = "no-cache";
    }
    await next();
});
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.DocumentTitle = "MoyKabinet API";
        options.DisplayRequestDuration();
    });
}
app.UseRateLimiter();
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapGet("/book", (IWebHostEnvironment environment) => Results.File(Path.Combine(environment.WebRootPath, "index.html"), "text/html; charset=utf-8"));
app.MapGet("/health", () => Results.Ok(new { ok = true }));
app.MapAuthEndpoints();
app.MapCabinetEndpoints();

await using (var scope = app.Services.CreateAsyncScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var source = db.Database.GetConnectionString()?.Replace("Data Source=", "", StringComparison.OrdinalIgnoreCase);
    var directory = source is null ? null : Path.GetDirectoryName(source);
    if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
    await db.Database.MigrateAsync();
}

app.Run();
public partial class Program;
