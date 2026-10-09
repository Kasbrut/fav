import 'package:fav/features/install/domain/advanced_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the advanced installation options edited across the form screens.
class InstallFormController extends Notifier<AdvancedOptions> {
  @override
  AdvancedOptions build() => const AdvancedOptions();

  /// The advanced options currently held by the form.
  AdvancedOptions get options => state;

  /// Replaces the current options.
  set options(AdvancedOptions value) => state = value;

  /// Restores the spec default options.
  void reset() => state = const AdvancedOptions();
}

/// Carries the advanced options between the add-server and advanced forms.
final NotifierProvider<InstallFormController, AdvancedOptions>
installFormProvider =
    NotifierProvider.autoDispose<InstallFormController, AdvancedOptions>(
      InstallFormController.new,
    );
