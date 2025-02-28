// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

class WallpaperSelectorViewController: WallpaperBaseViewController, Loggable {

    private struct UX {
        static let cardWidth: CGFloat = UIDevice().isTinyFormFactor ? 88 : 97
        static let cardHeight: CGFloat = UIDevice().isTinyFormFactor ? 80 : 88
        static let inset: CGFloat = 8
        static let cardShadowHeight: CGFloat = 14
    }

    private var viewModel: WallpaperSelectorViewModel
    internal var notificationCenter: NotificationProtocol

    // Views
    private lazy var contentView: UIView = .build { _ in }
    private var collectionViewHeightConstraint: NSLayoutConstraint!

    private lazy var headerLabel: UILabel = .build { label in
        label.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .headline,
                                                                   size: 17)
        label.adjustsFontForContentSizeCategory = true
        label.text = .Onboarding.WallpaperSelectorTitle
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = AccessibilityIdentifiers.Onboarding.Wallpaper.title
    }

    private lazy var instructionLabel: UILabel = .build { label in
        label.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .body,
                                                                   size: 12)
        label.adjustsFontForContentSizeCategory = true
        label.text = .Onboarding.WallpaperSelectorDescription
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = AccessibilityIdentifiers.Onboarding.Wallpaper.description
    }

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero,
                                              collectionViewLayout: getCompositionalLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        collectionView.register(
            WallpaperCollectionViewCell.self,
            forCellWithReuseIdentifier: WallpaperCollectionViewCell.cellIdentifier)
        return collectionView
    }()

    private lazy var settingsButton: ResizableButton = .build { button in
        button.titleLabel?.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .body,
                                                                                size: 16)
        button.titleLabel?.textAlignment = .center
        button.setTitle(.Onboarding.WallpaperSelectorAction, for: .normal)
        button.accessibilityIdentifier = AccessibilityIdentifiers.Onboarding.Wallpaper.settingsButton
    }

    // MARK: - Initializers
    init(viewModel: WallpaperSelectorViewModel,
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.viewModel = viewModel
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View setup & lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        applyTheme()
        setupNotifications(forObserver: self, observing: [.DisplayThemeChanged])
        settingsButton.addTarget(self, action: #selector(self.settingsButtonTapped), for: .touchUpInside)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()

        // make collection view fixed height so the bottom sheet can size correctly
        let height = collectionView.collectionViewLayout.collectionViewContentSize.height +
            WallpaperSelectorViewController.UX.cardShadowHeight
        collectionViewHeightConstraint.constant = height
        view.layoutIfNeeded()

        collectionView.selectItem(at: viewModel.selectedIndexPath, animated: false, scrollPosition: [])

        viewModel.sendImpressionTelemetry()
    }

    override func updateOnRotation() {
        configureCollectionView()
    }
}

// MARK: - CollectionView Data Source
extension WallpaperSelectorViewController: UICollectionViewDelegate, UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.numberOfWallpapers
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: WallpaperCollectionViewCell.cellIdentifier,
                                                            for: indexPath) as? WallpaperCollectionViewCell,
              let cellViewModel = viewModel.cellViewModel(for: indexPath)
        else { return UICollectionViewCell() }

        cell.viewModel = cellViewModel
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        downloadAndSetWallpaper(at: indexPath)
    }
}

// MARK: - Private
private extension WallpaperSelectorViewController {

    func setupView() {
        configureCollectionView()

        contentView.addSubviews(headerLabel, instructionLabel, collectionView, settingsButton)
        view.addSubview(contentView)

        collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 300)
        collectionViewHeightConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            headerLabel.bottomAnchor.constraint(equalTo: instructionLabel.topAnchor, constant: -4),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            instructionLabel.bottomAnchor.constraint(equalTo: collectionView.topAnchor, constant: -32),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -14),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionViewHeightConstraint,

            settingsButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            settingsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -43),
            settingsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
        ])
    }

    func configureCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.collectionViewLayout = getCompositionalLayout()
    }

    func getCompositionalLayout() -> UICollectionViewCompositionalLayout {
        viewModel.updateSectionLayout(for: traitCollection)

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .vertical

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { ix, environment in
            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(WallpaperSelectorViewController.UX.cardWidth),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                   heightDimension: .absolute(WallpaperSelectorViewController.UX.cardHeight))
            let subitemsCount = self.viewModel.sectionLayout.itemsPerRow
            let subItems: [NSCollectionLayoutItem] = Array(repeating: item, count: Int(subitemsCount))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                           subitems: subItems)
            group.interItemSpacing = .fixed(WallpaperSelectorViewController.UX.inset)

            let section = NSCollectionLayoutSection(group: group)
            let width = environment.container.effectiveContentSize.width
            let inset = (width -
                         CGFloat(subitemsCount) * WallpaperSelectorViewController.UX.cardWidth -
                         CGFloat(subitemsCount - 1) * WallpaperSelectorViewController.UX.inset) / 2.0
            section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                            leading: inset,
                                                            bottom: 0,
                                                            trailing: inset)
            section.interGroupSpacing = WallpaperSelectorViewController.UX.inset
            return section
        }, configuration: config)

        return layout
    }

    func downloadAndSetWallpaper(at indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? WallpaperCollectionViewCell
            else { return }

        cell.showDownloading(true)

        viewModel.downloadAndSetWallpaper(at: indexPath) { [weak self] result in
            ensureMainThread {
                cell.showDownloading(false)

                guard case .failure(let error) = result else { return }

                self?.showError(error) { _ in
                    self?.downloadAndSetWallpaper(at: indexPath)
                }
            }
        }
    }

    /// Settings button tapped
    @objc func settingsButtonTapped(_ sender: UIButton) {
        viewModel.openSettingsAction()
    }
}

// TODO: FXIOS-4882 next PR to finish up homepage theming
// MARK: - Themable & Notifiable
extension WallpaperSelectorViewController: NotificationThemeable, Notifiable {

    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .DisplayThemeChanged:
            applyTheme()
        default: break
        }
    }

    func applyTheme() {
        let theme = BuiltinThemeName(rawValue: LegacyThemeManager.instance.current.name) ?? .normal
        if theme == .dark {
            contentView.backgroundColor = UIColor.Photon.DarkGrey40
            headerLabel.textColor = UIColor.Photon.LightGrey05
            instructionLabel.textColor = UIColor.Photon.LightGrey05
            settingsButton.setTitleColor(UIColor.Photon.LightGrey05, for: .normal)
        } else {
            contentView.backgroundColor = UIColor.Photon.LightGrey10
            headerLabel.textColor = UIColor.Photon.Ink80
            instructionLabel.textColor = UIColor.Photon.DarkGrey05
            settingsButton.setTitleColor(UIColor.Photon.Blue50, for: .normal)
        }
    }
}

extension WallpaperSelectorViewController: BottomSheetChild {
    func willDismiss() {
        viewModel.removeAssetsOnDismiss()
        viewModel.sendDismissImpressionTelemetry()
    }
}
