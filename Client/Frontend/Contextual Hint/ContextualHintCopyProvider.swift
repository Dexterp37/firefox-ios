// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

enum ContextualHintCopyType {
    case action, description
}

/// `ContextualHintCopyProvider` exists to provide the requested description or action strings back
/// for the specified `ContextualHintType`.
struct ContextualHintCopyProvider: FeatureFlaggable {
    typealias CFRStrings = String.ContextualHints

    /// Arrow direction infuences toolbar copy, so it exists here.
    private var arrowDirection: UIPopoverArrowDirection?

    init(arrowDirecton: UIPopoverArrowDirection? = nil) {
        self.arrowDirection = arrowDirecton
    }

    // MARK: - Public interface

    /// Returns the copy for the requested part of the CFR (`ContextualHintCopyType`) for the specified
    /// hint.
    ///
    /// - Parameters:
    ///   - copyType: The requested part of the CFR copy to return.
    ///   - hint: The `ContextualHintType` for which a consumer wants copy for.
    /// - Returns: The requested copy.
    func getCopyFor(_ copyType: ContextualHintCopyType, of hint: ContextualHintType) -> String {
        var copyToReturn: String

        switch copyType {
        case .action:
            copyToReturn = getActionCopyFor(hint)
        case .description:
            copyToReturn = getDescriptionCopyFor(hint)
        }

        return copyToReturn
    }

    // MARK: - Private helpers

    private func getDescriptionCopyFor(_ hint: ContextualHintType) -> String {
        var descriptionCopy = ""

        switch hint {
        case .inactiveTabs:
            descriptionCopy = CFRStrings.TabsTray.InactiveTabs.Body

        case .jumpBackIn:
            let shouldShowNew = featureFlags.isFeatureEnabled(.copyForJumpBackIn, checking: .buildOnly)

            if shouldShowNew {
                descriptionCopy = CFRStrings.FirefoxHomepage.JumpBackIn.PersonalizedHome
            } else {
                descriptionCopy = CFRStrings.FirefoxHomepage.JumpBackIn.PersonalizedHomeOldCopy
            }

        case .jumpBackInSyncedTab:
            descriptionCopy = CFRStrings.FirefoxHomepage.JumpBackIn.SyncedTab

            /// Toolbar description copy depends on the arrow direction.
        case .toolbarLocation:
            let shouldShowNew = featureFlags.isFeatureEnabled(.copyForToolbar, checking: .buildOnly)

            return getToolbarDescriptionCopy(with: arrowDirection, and: shouldShowNew)
        }

        return descriptionCopy
    }

    private func getActionCopyFor(_ hint: ContextualHintType) -> String {
        var actionCopy: String

        switch hint {
        case .inactiveTabs:
            actionCopy = CFRStrings.TabsTray.InactiveTabs.Action
        case .toolbarLocation:
            actionCopy = CFRStrings.Toolbar.SearchBarPlacementButtonText
        case .jumpBackIn,
                .jumpBackInSyncedTab:
            actionCopy = ""
        }

        return actionCopy
    }

    // MARK: - Private helpers

    private func getToolbarDescriptionCopy(with arrowDirection: UIPopoverArrowDirection?, and shouldShowNew: Bool) -> String {
        /// Toolbar description should never be empty! If it is, find where this struct is being
        /// created for toolbar and ensure there's an arrowDirection passed.
        guard let arrowDirection = arrowDirection else { return "" }

        switch arrowDirection {
        case .up:
            return shouldShowNew ? CFRStrings.Toolbar.SearchBarTopPlacement : CFRStrings.Toolbar.SearchBarPlacementForExistingUsers
        case .down:
            return shouldShowNew ? CFRStrings.Toolbar.SearchBarBottomPlacement : CFRStrings.Toolbar.SearchBarPlacementForNewUsers
        default: return ""
        }

    }

}
