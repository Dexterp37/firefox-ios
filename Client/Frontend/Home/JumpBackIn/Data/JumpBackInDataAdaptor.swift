// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Storage

protocol JumpBackInDataAdaptor {
    var hasSyncedTabFeatureEnabled: Bool { get }

    func getRecentTabData() -> [Tab]
    func getGroupsData() -> [ASGroup<Tab>]?
    func getSyncedTabData() -> JumpBackInSyncedTab?

    func getHeroImage(forSite site: Site) -> UIImage?
    func getFaviconImage(forSite site: Site) -> UIImage?
}

protocol JumpBackInDelegate: AnyObject {
    func didLoadNewData()
}

class JumpBackInDataAdaptorImplementation: JumpBackInDataAdaptor, FeatureFlaggable {

    // MARK: Properties

    var notificationCenter: NotificationProtocol
    private let profile: Profile
    private let tabManager: TabManagerProtocol
    private var siteImageHelper: SiteImageHelperProtocol
    private var heroImages = [String: UIImage]() {
        didSet {
            delegate?.didLoadNewData()
        }
    }

    private var faviconImages = [String: UIImage]() {
        didSet {
            delegate?.didLoadNewData()
        }
    }

    private var recentTabs: [Tab] = [Tab]()
    private var recentGroups: [ASGroup<Tab>]?
    private var mostRecentSyncedTab: JumpBackInSyncedTab?
    private var hasSyncAccount: Bool?

    private let userInitiatedQueue: DispatchQueueInterface

    weak var delegate: JumpBackInDelegate?

    // MARK: Init
    init(profile: Profile,
         tabManager: TabManagerProtocol,
         siteImageHelper: SiteImageHelperProtocol,
         userInitiatedQueue: DispatchQueueInterface = DispatchQueue.global(qos: DispatchQoS.userInitiated.qosClass),
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.profile = profile
        self.tabManager = tabManager
        self.siteImageHelper = siteImageHelper
        self.notificationCenter = notificationCenter

        self.userInitiatedQueue = userInitiatedQueue

        setupNotifications(forObserver: self, observing: [.ShowHomepage,
                                                          .TabsTrayDidClose,
                                                          .TabsTrayDidSelectHomeTab,
                                                          .TopTabsTabClosed,
                                                          .ProfileDidFinishSyncing,
                                                          .FirefoxAccountChanged])

        userInitiatedQueue.async { [weak self] in
            self?.updateTabsAndAccountData()
        }
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    // MARK: Public interface

    var hasSyncedTabFeatureEnabled: Bool {
        return featureFlags.isFeatureEnabled(.jumpBackInSyncedTab, checking: .buildOnly) && hasSyncAccount ?? false
    }

    func getRecentTabData() -> [Tab] {
        return recentTabs
    }

    func getGroupsData() -> [ASGroup<Tab>]? {
        return recentGroups
    }

    func getSyncedTabData() -> JumpBackInSyncedTab? {
        return mostRecentSyncedTab
    }

    func getHeroImage(forSite site: Site) -> UIImage? {
        if let heroImage = heroImages[site.url] {
            return heroImage
        }
        siteImageHelper.fetchImageFor(site: site,
                                      imageType: .heroImage,
                                      shouldFallback: true) { image in
            self.heroImages[site.url] = image
        }
        return nil
    }

    func getFaviconImage(forSite site: Site) -> UIImage? {
        if let faviconImage = faviconImages[site.url] {
            return faviconImage
        }

        siteImageHelper.fetchImageFor(site: site,
                                      imageType: .favicon,
                                      shouldFallback: false) { image in
            self.faviconImages[site.url] = image
        }
        return nil
    }

    // MARK: Jump back in data

    private func updateTabsAndAccountData() {
        getHasSyncAccount { [weak self] in
            self?.updateTabsData()
        }
    }

    private func updateTabsData() {
        updateJumpBackInData { [weak self] in
            self?.delegate?.didLoadNewData()
        }

        updateRemoteTabs { [weak self] in
            self?.delegate?.didLoadNewData()
        }
    }

    /// Update data with tab and search term group managers, saving it in view model for further usage
    private func updateJumpBackInData(completion: @escaping () -> Void) {
        recentTabs = tabManager.recentlyAccessedNormalTabs

        if featureFlags.isFeatureEnabled(.tabTrayGroups, checking: .buildAndUser) {
            SearchTermGroupsUtility.getTabGroups(
                with: self.profile,
                from: self.recentTabs,
                using: .orderedDescending
            ) { [weak self] groups, _ in

                self?.recentGroups = groups
                completion()
            }
        } else {
            completion()
        }
    }

    // MARK: Synced tab data

    private func getHasSyncAccount(completion: @escaping () -> Void) {
        guard featureFlags.isFeatureEnabled(.jumpBackInSyncedTab, checking: .buildOnly) else {
            completion()
            return
        }

        profile.hasSyncAccount { hasSync in
            self.hasSyncAccount = hasSync
            completion()
        }
    }

    private func updateRemoteTabs(completion: @escaping () -> Void) {
        // Short circuit if the user is not logged in or feature not enabled
        guard hasSyncedTabFeatureEnabled else {
            mostRecentSyncedTab = nil
            completion()
            return
        }

        // Get cached tabs
        profile.getCachedClientsAndTabs { [weak self] result in
            self?.createMostRecentSyncedTab(from: result, completion: completion)
        }
    }

    private func createMostRecentSyncedTab(from clientAndTabs: [ClientAndTabs], completion: @escaping () -> Void) {
        // filter clients for non empty desktop clients
        let desktopClientAndTabs = clientAndTabs.filter { !$0.tabs.isEmpty &&
            ClientType.fromFxAType($0.client.type) == .Desktop }

        guard !desktopClientAndTabs.isEmpty, !clientAndTabs.isEmpty else {
            mostRecentSyncedTab = nil
            completion()
            return
        }

        // get most recent tab
        var mostRecentTab: (client: RemoteClient, tab: RemoteTab)?

        desktopClientAndTabs.forEach { remoteClient in
            guard let firstClient = remoteClient.tabs.first else { return }
            let mostRecentClientTab = remoteClient.tabs.reduce(firstClient, {
                                                                $0.lastUsed > $1.lastUsed ? $0 : $1 })

            if let currentMostRecentTab = mostRecentTab,
               currentMostRecentTab.tab.lastUsed < mostRecentClientTab.lastUsed {
                mostRecentTab = (client: remoteClient.client, tab: mostRecentClientTab)
            } else if mostRecentTab == nil {
                mostRecentTab = (client: remoteClient.client, tab: mostRecentClientTab)
            }
        }

        guard let mostRecentTab = mostRecentTab else {
            mostRecentSyncedTab = nil
            completion()
            return
        }

        mostRecentSyncedTab = JumpBackInSyncedTab(client: mostRecentTab.client, tab: mostRecentTab.tab)
        completion()
    }
}

// MARK: - Notifiable
extension JumpBackInDataAdaptorImplementation: Notifiable {
    func handleNotifications(_ notification: Notification) {
        userInitiatedQueue.async { [weak self] in
            switch notification.name {
            case .ShowHomepage,
                    .TabsTrayDidClose,
                    .TabsTrayDidSelectHomeTab,
                    .TopTabsTabClosed:
                self?.updateTabsData()
            case .ProfileDidFinishSyncing,
                    .FirefoxAccountChanged:
                self?.updateTabsAndAccountData()
            default: break
            }
        }
    }
}
