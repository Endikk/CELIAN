using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace Api.Caching;

/// <summary>
/// The check of the server certificate of the cache, under TLS (research
/// RS-11): the certificate must chain to a certificate of the CA bundle that
/// the target layer mounts, and to nothing else, not even an authority that
/// the machine trusts. VerifyFull also wants the name of CACHE_HOST in the
/// certificate. Revocation is not checked: the bundle of the target is the
/// only trust, and the check makes no network call.
/// </summary>
public static class CacheCertificateValidation
{
    private static readonly Oid ServerAuthentication = new("1.3.6.1.5.5.7.3.1");

    public static RemoteCertificateValidationCallback Create(X509Certificate2Collection authorities, CacheTlsMode mode)
    {
        ArgumentNullException.ThrowIfNull(authorities);
        if (mode == CacheTlsMode.Disable)
        {
            throw new ArgumentException("A connection without TLS has no certificate to check.", nameof(mode));
        }

        if (authorities.Count == 0)
        {
            throw new ArgumentException("The CA bundle of the cache holds no certificate.", nameof(authorities));
        }

        var checkName = mode == CacheTlsMode.VerifyFull;
        return (_, certificate, _, errors) => IsTrusted(certificate, errors, authorities, checkName);
    }

    private static bool IsTrusted(X509Certificate? certificate, SslPolicyErrors errors, X509Certificate2Collection authorities, bool checkName)
    {
        if (certificate is null || errors.HasFlag(SslPolicyErrors.RemoteCertificateNotAvailable))
        {
            return false;
        }

        if (checkName && errors.HasFlag(SslPolicyErrors.RemoteCertificateNameMismatch))
        {
            return false;
        }

        var owned = certificate is not X509Certificate2;
        var server = certificate as X509Certificate2 ?? X509CertificateLoader.LoadCertificate(certificate.GetRawCertData());
        try
        {
            using var chain = new X509Chain();
            chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
            chain.ChainPolicy.CustomTrustStore.AddRange(authorities);
            chain.ChainPolicy.ExtraStore.AddRange(authorities);
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            chain.ChainPolicy.ApplicationPolicy.Add(ServerAuthentication);
            return chain.Build(server);
        }
        finally
        {
            if (owned)
            {
                server.Dispose();
            }
        }
    }
}
