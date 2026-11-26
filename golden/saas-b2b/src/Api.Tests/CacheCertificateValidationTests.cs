using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Api.Caching;

namespace Api.Tests;

/// <summary>Certificates made for the tests, in memory, never written outside a temporary file.</summary>
public static class TestCertificates
{
    private static readonly Oid ServerAuthentication = new("1.3.6.1.5.5.7.3.1");

    public static X509Certificate2 Authority(string name = "CN=Test cache authority")
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest(name, key, HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));
        var now = DateTimeOffset.UtcNow;
        return request.CreateSelfSigned(now.AddDays(-1), now.AddDays(30));
    }

    public static X509Certificate2 Server(X509Certificate2 authority, string host)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest($"CN={host}", key, HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, false));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension([ServerAuthentication], false));
        var names = new SubjectAlternativeNameBuilder();
        names.AddDnsName(host);
        request.CertificateExtensions.Add(names.Build());
        var now = DateTimeOffset.UtcNow;
        using var certificate = request.Create(authority, now.AddHours(-1), now.AddDays(7), RandomNumberGenerator.GetBytes(16));
        return certificate.CopyWithPrivateKey(key);
    }
}

/// <summary>
/// TLS to the cache (research RS-11; ADR-015, condition 17): the server
/// certificate must chain to a certificate of the CA bundle of the target,
/// and to nothing else; VerifyFull also wants the name to match.
/// </summary>
public sealed class CacheCertificateValidationTests : IDisposable
{
    private const SslPolicyErrors ChainErrors = SslPolicyErrors.RemoteCertificateChainErrors;

    private const SslPolicyErrors NameMismatch = SslPolicyErrors.RemoteCertificateNameMismatch;

    private readonly X509Certificate2 _authority = TestCertificates.Authority();

    private readonly X509Certificate2 _other = TestCertificates.Authority("CN=Another authority");

    private readonly X509Certificate2 _server;

    public CacheCertificateValidationTests()
    {
        _server = TestCertificates.Server(_authority, "cache.test");
    }

    public void Dispose()
    {
        _authority.Dispose();
        _other.Dispose();
        _server.Dispose();
    }

    private static RemoteCertificateValidationCallback Validation(CacheTlsMode mode, params X509Certificate2[] authorities) =>
        CacheCertificateValidation.Create(new X509Certificate2Collection(authorities), mode);

    [Theory]
    [InlineData(CacheTlsMode.VerifyCA)]
    [InlineData(CacheTlsMode.VerifyFull)]
    public void A_certificate_of_the_bundle_authority_is_accepted(CacheTlsMode mode)
    {
        Assert.True(Validation(mode, _authority)(this, _server, null, ChainErrors));
    }

    [Fact]
    public void VerifyFull_refuses_a_name_that_does_not_match()
    {
        Assert.False(Validation(CacheTlsMode.VerifyFull, _authority)(this, _server, null, ChainErrors | NameMismatch));
    }

    [Fact]
    public void VerifyCA_accepts_a_name_that_does_not_match()
    {
        Assert.True(Validation(CacheTlsMode.VerifyCA, _authority)(this, _server, null, ChainErrors | NameMismatch));
    }

    [Theory]
    [InlineData(CacheTlsMode.VerifyCA)]
    [InlineData(CacheTlsMode.VerifyFull)]
    public void A_certificate_of_another_authority_is_refused(CacheTlsMode mode)
    {
        Assert.False(Validation(mode, _other)(this, _server, null, ChainErrors));
    }

    [Fact]
    public void A_certificate_that_the_machine_trusts_is_still_checked_against_the_bundle()
    {
        Assert.False(Validation(CacheTlsMode.VerifyFull, _other)(this, _server, null, SslPolicyErrors.None));
    }

    [Fact]
    public void The_authority_may_come_anywhere_in_the_bundle()
    {
        Assert.True(Validation(CacheTlsMode.VerifyFull, _other, _authority)(this, _server, null, ChainErrors));
    }

    [Fact]
    public void A_missing_certificate_is_refused()
    {
        Assert.False(Validation(CacheTlsMode.VerifyCA, _authority)(this, null, null, SslPolicyErrors.RemoteCertificateNotAvailable));
    }

    [Fact]
    public void An_empty_bundle_is_refused_at_creation()
    {
        Assert.Throws<ArgumentException>(() => CacheCertificateValidation.Create([], CacheTlsMode.VerifyFull));
    }

    [Fact]
    public void Disable_has_no_validation()
    {
        Assert.Throws<ArgumentException>(() => CacheCertificateValidation.Create(new X509Certificate2Collection(_authority), CacheTlsMode.Disable));
    }
}
