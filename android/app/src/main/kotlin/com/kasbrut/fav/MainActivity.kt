package com.kasbrut.fav

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): required by local_auth,
// whose BiometricPrompt needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity()
