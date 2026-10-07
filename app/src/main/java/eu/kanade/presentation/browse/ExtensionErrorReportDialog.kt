package eu.kanade.presentation.browse

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import eu.kanade.tachiyomi.extension.ExtensionErrorReport
import tachiyomi.i18n.MR
import tachiyomi.i18n.kmk.KMR
import tachiyomi.presentation.core.i18n.stringResource

/**
 * Asks the user to report a broken extension to whoever maintains it.
 *
 * The wording is deliberately explicit about where a report belongs: an extension that fails because a
 * site changed cannot be fixed by this app, so a report sent to the app's own support channels is
 * both pointless and slow for everyone.
 *
 * The action is a GitHub issue search scoped to the extension's own repository, rather than a link to
 * a chat server. Pointing every user at one invite floods its maintainers with identical reports and
 * buries anything else they are trying to read; a scoped search lets them find the issue tracker,
 * see whether it is already reported, and add to an existing report instead of duplicating it.
 */
@Composable
fun ExtensionErrorReportDialog(
    report: ExtensionErrorReport,
    onOk: () -> Unit,
    onDontShowAgain: () -> Unit,
    onSearchGitHub: (String) -> Unit,
    onCopyReport: () -> Unit,
) {
    val extensionName = report.extensionName.ifBlank { report.pkgName }
    val repoName = report.repoName

    AlertDialog(
        onDismissRequest = onOk,
        properties = DialogProperties(dismissOnClickOutside = true),
        title = {
            Text(stringResource(KMR.strings.ext_error_report_title, extensionName))
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = if (repoName.isNullOrBlank()) {
                        stringResource(
                            KMR.strings.ext_error_report_no_repo,
                            extensionName,
                            report.reason,
                        )
                    } else {
                        stringResource(
                            KMR.strings.ext_error_report_body,
                            extensionName,
                            report.versionName,
                            repoName,
                            report.reason,
                        )
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = stringResource(KMR.strings.ext_error_search_github),
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clickable { onSearchGitHub(report.searchUrl) },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = stringResource(KMR.strings.ext_error_copy_report),
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clickable(onClick = onCopyReport),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onOk) {
                Text(stringResource(MR.strings.action_ok))
            }
        },
        dismissButton = {
            TextButton(onClick = onDontShowAgain) {
                Text(stringResource(KMR.strings.ext_error_report_dont_show_again))
            }
        },
    )
}
