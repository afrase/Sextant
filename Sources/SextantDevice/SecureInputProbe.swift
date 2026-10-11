import Carbon

/// Whether another app has secure keyboard entry on (a password field, Terminal's Secure Keyboard Entry).
/// The live view pauses key highlights while it is.
public enum SecureInputProbe {
    public static let isEnabled: @Sendable () -> Bool = { IsSecureEventInputEnabled() }
}
