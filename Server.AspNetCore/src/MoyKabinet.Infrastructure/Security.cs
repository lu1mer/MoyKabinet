using System.Security.Cryptography;
using System.Text;
using MoyKabinet.Application;

namespace MoyKabinet.Infrastructure;

public sealed class SystemClock : IClock { public DateTime UtcNow => DateTime.UtcNow; }

public sealed class SecretGenerator : ISecretGenerator
{
    public string Create(int bytes = 32) => Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(bytes));
    public string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    public bool Matches(string value, string hash)
    {
        try { return CryptographicOperations.FixedTimeEquals(Convert.FromHexString(Hash(value)), Convert.FromHexString(hash)); }
        catch (FormatException) { return false; }
    }
}

internal static class Base64UrlEncoder
{
    public static string Encode(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
