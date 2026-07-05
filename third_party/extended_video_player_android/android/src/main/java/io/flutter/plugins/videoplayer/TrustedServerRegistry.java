package io.flutter.plugins.videoplayer;

import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.Base64;
import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;
import okhttp3.CertificatePinner;
import okhttp3.OkHttpClient;

final class TrustedServerRegistry {
  private static final Map<String, OkHttpClient> clientsByHost = new ConcurrentHashMap<>();

  private TrustedServerRegistry() {}

  static void registerTrustedServer(
      @NonNull String serverUrl, @NonNull String rootCaPem, @Nullable String leafSha256)
      throws Exception {
    final Uri uri = Uri.parse(serverUrl);
    final String host = normalizeHost(uri.getHost());
    if (host == null || host.isEmpty()) {
      throw new IllegalArgumentException("serverUrl host is required");
    }
    if (rootCaPem.trim().isEmpty()) {
      throw new IllegalArgumentException("rootCaPem is required");
    }
    clientsByHost.put(host, buildClient(host, rootCaPem, leafSha256));
  }

  static void clearTrustedServers() {
    clientsByHost.clear();
  }

  @Nullable
  static OkHttpClient findClient(@NonNull Uri uri) {
    final String host = normalizeHost(uri.getHost());
    if (host == null || host.isEmpty()) {
      return null;
    }
    return clientsByHost.get(host);
  }

  @NonNull
  private static OkHttpClient buildClient(
      @NonNull String host, @NonNull String rootCaPem, @Nullable String leafSha256)
      throws Exception {
    final X509TrustManager trustManager = buildTrustManager(rootCaPem);
    final SSLContext sslContext = SSLContext.getInstance("TLS");
    sslContext.init(null, new TrustManager[] {trustManager}, new SecureRandom());

    final OkHttpClient.Builder builder =
        new OkHttpClient.Builder()
            .sslSocketFactory(sslContext.getSocketFactory(), trustManager)
            .retryOnConnectionFailure(true);

    final String normalizedLeafSha256 = normalizeSha256(leafSha256);
    if (normalizedLeafSha256 != null) {
      builder.certificatePinner(
          new CertificatePinner.Builder()
              .add(host, "sha256/" + hexToBase64(normalizedLeafSha256))
              .build());
    }
    return builder.build();
  }

  @NonNull
  private static X509TrustManager buildTrustManager(@NonNull String rootCaPem) throws Exception {
    final CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");
    final Collection<? extends Certificate> certificates =
        certificateFactory.generateCertificates(
            new ByteArrayInputStream(rootCaPem.getBytes(StandardCharsets.UTF_8)));
    if (certificates.isEmpty()) {
      throw new IllegalArgumentException("No certificates found in rootCaPem");
    }

    final KeyStore keyStore = KeyStore.getInstance(KeyStore.getDefaultType());
    keyStore.load(null, null);
    int index = 0;
    for (Certificate certificate : certificates) {
      keyStore.setCertificateEntry("nas-trusted-" + index++, certificate);
    }

    final TrustManagerFactory trustManagerFactory =
        TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
    trustManagerFactory.init(keyStore);
    for (TrustManager trustManager : trustManagerFactory.getTrustManagers()) {
      if (trustManager instanceof X509TrustManager) {
        return (X509TrustManager) trustManager;
      }
    }
    throw new IllegalStateException("No X509TrustManager available");
  }

  @Nullable
  private static String normalizeHost(@Nullable String host) {
    if (host == null) {
      return null;
    }
    final String normalized = host.trim().toLowerCase(Locale.US);
    return normalized.isEmpty() ? null : normalized;
  }

  @Nullable
  private static String normalizeSha256(@Nullable String leafSha256) {
    if (leafSha256 == null) {
      return null;
    }
    final String normalized = leafSha256.trim().toLowerCase(Locale.US);
    return normalized.isEmpty() ? null : normalized;
  }

  @NonNull
  private static String hexToBase64(@NonNull String hex) {
    final int length = hex.length();
    if (length % 2 != 0) {
      throw new IllegalArgumentException("Invalid hex-encoded SHA-256 value");
    }
    final byte[] bytes = new byte[length / 2];
    for (int index = 0; index < length; index += 2) {
      bytes[index / 2] = (byte) Integer.parseInt(hex.substring(index, index + 2), 16);
    }
    return Base64.getEncoder().encodeToString(bytes);
  }
}
