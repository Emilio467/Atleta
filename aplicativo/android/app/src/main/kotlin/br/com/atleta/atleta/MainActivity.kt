package br.com.atleta.atleta

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) explainHealthAccess(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        explainHealthAccess(intent)
    }

    private fun explainHealthAccess(intent: Intent?) {
        if (intent?.action != ACTION_SHOW_PERMISSIONS_RATIONALE &&
            intent?.action != ACTION_VIEW_PERMISSION_USAGE
        ) return

        AlertDialog.Builder(this)
            .setTitle(R.string.health_privacy_title)
            .setMessage(R.string.health_privacy_body)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private companion object {
        const val ACTION_SHOW_PERMISSIONS_RATIONALE = "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"
        const val ACTION_VIEW_PERMISSION_USAGE = "android.intent.action.VIEW_PERMISSION_USAGE"
    }
}
