using System.Net;
using System.Net.Mail;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MoyKabinet.Application;

namespace MoyKabinet.Infrastructure;

public sealed class AccountMailer(IConfiguration configuration, IHostEnvironment environment, ILogger<AccountMailer> logger) : IAccountMailer
{
    public async Task SendVerificationCodeAsync(string email, string code, CancellationToken cancellationToken)
        => await SendAsync(email, code, "Код подтверждения · Мой кабинет", cancellationToken);

    public async Task SendPasswordResetCodeAsync(string email, string code, CancellationToken cancellationToken)
        => await SendAsync(email, code, "Восстановление пароля · Мой кабинет", cancellationToken);

    private async Task SendAsync(string email, string code, string subject, CancellationToken cancellationToken)
    {
        var host = configuration["Email:SmtpHost"];
        if (string.IsNullOrWhiteSpace(host))
        {
            if (environment.IsDevelopment()) { logger.LogInformation("Development verification code for {Email}: {Code}", email, code); return; }
            throw new AppProblem(503, "Отправка email временно не настроена.");
        }
        using var client = new SmtpClient(host, configuration.GetValue("Email:SmtpPort", 587))
        {
            EnableSsl = configuration.GetValue("Email:UseTls", true),
            Credentials = new NetworkCredential(configuration["Email:Username"], configuration["Email:Password"])
        };
        using var message = new MailMessage(configuration["Email:From"] ?? "noreply@moykabinet.app", email)
        {
            Subject = subject,
            Body = $"Ваш код: {code}\n\nКод действует 10 минут. Если вы не регистрировались, просто проигнорируйте письмо."
        };
        await client.SendMailAsync(message, cancellationToken);
    }
}
