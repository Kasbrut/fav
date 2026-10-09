import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/profile/data/secure_client_profile_repository.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/profile/domain/profile_contract_validator.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// The raw `.conf` plus its parsed form, fetched from secure storage.
typedef ClientProfileBundle = ({String rawConf, ClientProfile profile});

/// Loads the client profile saved under a given server id (spec §8.6).
///
/// Returns `null` when no profile has been persisted for the server; throws
/// when the stored text fails to parse (corrupted storage).
final FutureProviderFamily<ClientProfileBundle?, String> clientProfileProvider =
    FutureProvider.autoDispose.family<ClientProfileBundle?, String>(
      (ref, serverId) async {
        final raw = await ref
            .watch(clientProfileRepositoryProvider)
            .getRaw(serverId);
        if (raw == null) {
          return null;
        }
        final server = await ref
            .watch(serverRepositoryProvider)
            .getById(serverId);
        final installation = server?.installation;
        final network = installation?.network;
        if (network != null && network.status != NetworkMetadataStatus.legacy) {
          if (!network.isStructurallyValidV2) {
            throw AppException(
              ErrorCode.scriptInvalid,
              detail:
                  'profile export blocked by ${network.status.name} '
                  'network metadata',
            );
          }
          final profile = await const ClientProfileParser().parse(
            raw,
            requireV2: true,
            ipv6Mode: network.ipv6Mode,
          );
          final problem = profileV2Problem(
            profile: profile,
            network: network,
            expectedServerPublicKey: installation?.serverPublicKey,
          );
          if (problem != null) {
            throw AppException(ErrorCode.scriptInvalid, detail: problem);
          }
          return (rawConf: raw, profile: profile);
        }
        final profile = await const ClientProfileParser().parse(raw);
        return (rawConf: raw, profile: profile);
      },
    );
