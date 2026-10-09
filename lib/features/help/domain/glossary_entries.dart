import 'package:meta/meta.dart';

/// A single entry in the Help glossary. Each entry is a plain-language
/// definition of a technical term shown on `/help/glossary` and addressable
/// individually via `/help/glossary/<slug>` (scroll-to-anchor).
@immutable
class GlossaryEntry {
  /// Creates a glossary entry.
  const GlossaryEntry({
    required this.slug,
    required this.titleKey,
    required this.bodyKey,
  });

  /// URL-safe identifier, used in markdown links (`glossary://<slug>`) and
  /// as the deep-link parameter for the glossary screen.
  final String slug;

  /// ARB key for the term's short title (e.g. "MTU").
  final String titleKey;

  /// ARB key for the term's body (1-2 paragraphs, plain language).
  final String bodyKey;
}

/// v1 glossary seed (15 terms). Ordering here is the display order on
/// `GlossaryScreen` (alphabetical by English title).
const List<GlossaryEntry> glossaryEntries = [
  GlossaryEntry(
    slug: 'allowed-ips',
    titleKey: 'glossaryAllowedIpsTitle',
    bodyKey: 'glossaryAllowedIpsBody',
  ),
  GlossaryEntry(
    slug: 'dns',
    titleKey: 'glossaryDnsTitle',
    bodyKey: 'glossaryDnsBody',
  ),
  GlossaryEntry(
    slug: 'fingerprint',
    titleKey: 'glossaryFingerprintTitle',
    bodyKey: 'glossaryFingerprintBody',
  ),
  GlossaryEntry(
    slug: 'firewall',
    titleKey: 'glossaryFirewallTitle',
    bodyKey: 'glossaryFirewallBody',
  ),
  GlossaryEntry(
    slug: 'handshake',
    titleKey: 'glossaryHandshakeTitle',
    bodyKey: 'glossaryHandshakeBody',
  ),
  GlossaryEntry(
    slug: 'mtu',
    titleKey: 'glossaryMtuTitle',
    bodyKey: 'glossaryMtuBody',
  ),
  GlossaryEntry(
    slug: 'peer',
    titleKey: 'glossaryPeerTitle',
    bodyKey: 'glossaryPeerBody',
  ),
  GlossaryEntry(
    slug: 'public-private-key',
    titleKey: 'glossaryPublicPrivateKeyTitle',
    bodyKey: 'glossaryPublicPrivateKeyBody',
  ),
  GlossaryEntry(
    slug: 'ssh',
    titleKey: 'glossarySshTitle',
    bodyKey: 'glossarySshBody',
  ),
  GlossaryEntry(
    slug: 'ssh-hardening',
    titleKey: 'glossaryHardeningTitle',
    bodyKey: 'glossaryHardeningBody',
  ),
  GlossaryEntry(
    slug: 'subnet',
    titleKey: 'glossarySubnetTitle',
    bodyKey: 'glossarySubnetBody',
  ),
  GlossaryEntry(
    slug: 'sudo',
    titleKey: 'glossarySudoTitle',
    bodyKey: 'glossarySudoBody',
  ),
  GlossaryEntry(
    slug: 'udp-port',
    titleKey: 'glossaryUdpPortTitle',
    bodyKey: 'glossaryUdpPortBody',
  ),
  GlossaryEntry(
    slug: 'vpn',
    titleKey: 'glossaryVpnTitle',
    bodyKey: 'glossaryVpnBody',
  ),
  GlossaryEntry(
    slug: 'wireguard',
    titleKey: 'glossaryWireguardTitle',
    bodyKey: 'glossaryWireguardBody',
  ),
];
