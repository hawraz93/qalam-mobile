package iq.edu.alqalam.qalam_notify

import androidx.core.content.FileProvider

/** Own subclass so its manifest entry never clashes with a plugin's FileProvider. */
class UpdateFileProvider : FileProvider()
