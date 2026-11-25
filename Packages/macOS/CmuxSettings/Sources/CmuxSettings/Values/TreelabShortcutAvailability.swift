public import CmuxFoundation

extension ShortcutAction {
    /// Shortcuts a brand does not offer, hidden from Settings and its search like the ones the
    /// build does not offer (``hostUnavailableActions``).
    ///
    /// - Parameter branding: The app's brand.
    /// - Returns: The hidden actions: Send Feedback when the brand offers no Manaflow service
    ///   (Treelab); none for upstream cmux.
    public static func brandUnavailableActions(branding: AppBranding) -> Set<ShortcutAction> {
        branding.offersManaflowServices ? [] : [.sendFeedback]
    }
}
