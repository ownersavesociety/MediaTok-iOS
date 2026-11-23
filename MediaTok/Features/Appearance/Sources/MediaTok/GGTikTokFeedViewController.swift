import Foundation
import UIKit
import AVFoundation
import Postbox
import TelegramPresentationData
import TelegramCore
import AccountContext
import Display
import SwiftSignalKit
import GGCore
import GGHooks

/// Unified TikTok / Reels Vertical Channel Video Feed (#187)
/// Vertical swipe player for videos & round video messages across subscribed channels!
public final class GGTikTokFeedViewController: UIViewController {
    private let context: AccountContext
    private weak var hostNavigationController: NavigationController?
    private var videoItems: [VideoFeedItem] = []
    private var currentIndex: Int = 0
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    private let titleLabel = UILabel()
    private let counterLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let videoContainer = UIView()
    private let channelLabel = UILabel()
    private let captionLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let chatButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let heartOverlay = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var isMuted: Bool = false
    private var searchDisposable: Disposable?
    private var fetchDisposable: Disposable?
    private var mediaDisposable: Disposable?
    private var activeTempVideoURL: URL?

    public struct VideoFeedItem {
        public let messageId: MessageId
        public let timestamp: Int32
        public let peer: EnginePeer?
        public let peerTitle: String
        public let caption: String
        public let resource: MediaResource?
        public let reference: MediaResourceReference?
    }

    public init(context: AccountContext, navigationController: NavigationController?) {
        self.context = context
        self.hostNavigationController = navigationController
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.searchDisposable?.dispose()
        self.fetchDisposable?.dispose()
        self.mediaDisposable?.dispose()
        if let obs = self.endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let tempURL = self.activeTempVideoURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        self.player?.pause()
        self.player = nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        self.setupUI()
        self.setupGestures()
        self.loadChannelVideos()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.player?.pause()
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if self.view.window == nil {
            self.player?.pause()
            self.player?.replaceCurrentItem(with: nil)
            self.playerLayer?.removeFromSuperlayer()
            self.player = nil
            self.playerLayer = nil
        }
    }

    private func setupUI() {
        self.videoContainer.translatesAutoresizingMaskIntoConstraints = false
        self.videoContainer.backgroundColor = .black
        self.view.addSubview(self.videoContainer)

        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.color = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        self.spinner.hidesWhenStopped = true
        self.view.addSubview(self.spinner)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.text = "🎬 TikTok-лента каналов"
        self.titleLabel.textColor = .white
        self.titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        self.view.addSubview(self.titleLabel)

        self.counterLabel.translatesAutoresizingMaskIntoConstraints = false
        self.counterLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        self.counterLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        self.view.addSubview(self.counterLabel)

        self.closeButton.translatesAutoresizingMaskIntoConstraints = false
        self.closeButton.setTitle("✕", for: .normal)
        self.closeButton.setTitleColor(.white, for: .normal)
        self.closeButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        self.closeButton.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.channelLabel.translatesAutoresizingMaskIntoConstraints = false
        self.channelLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        self.channelLabel.font = .systemFont(ofSize: 17, weight: .bold)
        self.channelLabel.isUserInteractionEnabled = true
        self.channelLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.channelTapped)))
        self.view.addSubview(self.channelLabel)

        self.captionLabel.translatesAutoresizingMaskIntoConstraints = false
        self.captionLabel.textColor = .white
        self.captionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        self.captionLabel.numberOfLines = 4
        self.view.addSubview(self.captionLabel)

        self.likeButton.translatesAutoresizingMaskIntoConstraints = false
        self.likeButton.setTitle("❤️", for: .normal)
        self.likeButton.titleLabel?.font = .systemFont(ofSize: 32)
        self.likeButton.addTarget(self, action: #selector(self.likeTapped), for: .touchUpInside)
        self.view.addSubview(self.likeButton)

        self.chatButton.translatesAutoresizingMaskIntoConstraints = false
        self.chatButton.setTitle("💬", for: .normal)
        self.chatButton.titleLabel?.font = .systemFont(ofSize: 30)
        self.chatButton.addTarget(self, action: #selector(self.channelTapped), for: .touchUpInside)
        self.view.addSubview(self.chatButton)

        self.muteButton.translatesAutoresizingMaskIntoConstraints = false
        self.muteButton.setTitle("🔊", for: .normal)
        self.muteButton.titleLabel?.font = .systemFont(ofSize: 28)
        self.muteButton.addTarget(self, action: #selector(self.muteTapped), for: .touchUpInside)
        self.view.addSubview(self.muteButton)

        self.heartOverlay.translatesAutoresizingMaskIntoConstraints = false
        self.heartOverlay.image = UIImage(systemName: "heart.fill")
        self.heartOverlay.tintColor = UIColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 0.92)
        self.heartOverlay.alpha = 0.0
        self.view.addSubview(self.heartOverlay)

        NSLayoutConstraint.activate([
            self.videoContainer.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.videoContainer.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.videoContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.videoContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.spinner.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),

            self.closeButton.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            self.closeButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 18),
            self.closeButton.widthAnchor.constraint(equalToConstant: 36),
            self.closeButton.heightAnchor.constraint(equalToConstant: 36),

            self.titleLabel.centerYAnchor.constraint(equalTo: self.closeButton.centerYAnchor),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.closeButton.trailingAnchor, constant: 12),

            self.counterLabel.centerYAnchor.constraint(equalTo: self.closeButton.centerYAnchor),
            self.counterLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -18),

            self.muteButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -18),
            self.muteButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            self.muteButton.widthAnchor.constraint(equalToConstant: 48),
            self.muteButton.heightAnchor.constraint(equalToConstant: 48),

            self.chatButton.trailingAnchor.constraint(equalTo: self.muteButton.trailingAnchor),
            self.chatButton.bottomAnchor.constraint(equalTo: self.muteButton.topAnchor, constant: -16),
            self.chatButton.widthAnchor.constraint(equalToConstant: 48),
            self.chatButton.heightAnchor.constraint(equalToConstant: 48),

            self.likeButton.trailingAnchor.constraint(equalTo: self.chatButton.trailingAnchor),
            self.likeButton.bottomAnchor.constraint(equalTo: self.chatButton.topAnchor, constant: -16),
            self.likeButton.widthAnchor.constraint(equalToConstant: 48),
            self.likeButton.heightAnchor.constraint(equalToConstant: 48),

            self.captionLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 18),
            self.captionLabel.trailingAnchor.constraint(equalTo: self.likeButton.leadingAnchor, constant: -16),
            self.captionLabel.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            self.channelLabel.leadingAnchor.constraint(equalTo: self.captionLabel.leadingAnchor),
            self.channelLabel.trailingAnchor.constraint(equalTo: self.captionLabel.trailingAnchor),
            self.channelLabel.bottomAnchor.constraint(equalTo: self.captionLabel.topAnchor, constant: -8),

            self.heartOverlay.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.heartOverlay.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            self.heartOverlay.widthAnchor.constraint(equalToConstant: 120),
            self.heartOverlay.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func setupGestures() {
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeUp))
        swipeUp.direction = .up
        self.view.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeDown))
        swipeDown.direction = .down
        self.view.addGestureRecognizer(swipeDown)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.handleSingleTap))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        self.view.addGestureRecognizer(singleTap)
        self.view.addGestureRecognizer(doubleTap)
    }

    private func loadChannelVideos() {
        self.spinner.startAnimating()
        let localSignal = self.context.account.postbox.transaction { transaction -> [VideoFeedItem] in
            var found: [VideoFeedItem] = []
            var seenMsgIds = Set<MessageId>()
            var seenPeers = Set<PeerId>()
            let groups: [PeerGroupId] = [.root, PeerGroupId(rawValue: 1)]
            for groupId in groups {
                let peers = transaction.getTopChatListEntries(groupId: groupId, count: 60)
                for rendered in peers {
                    if seenPeers.contains(rendered.peerId) { continue }
                    seenPeers.insert(rendered.peerId)
                    let peerObj = rendered.peer
                    let peerTitle = peerObj?.debugDisplayTitle ?? "Канал"
                    let enginePeer = peerObj.map(EnginePeer.init)
                    transaction.scanTopMessages(peerId: rendered.peerId, namespace: Namespaces.Message.Cloud, limit: 25) { message in
                        if seenMsgIds.contains(message.id) { return true }
                        for media in message.media {
                            if let file = media as? TelegramMediaFile,
                               (file.isVideo || file.isInstantVideo),
                               !file.isAnimated,
                               !file.isSticker,
                               !file.isAnimatedSticker {
                                seenMsgIds.insert(message.id)
                                let ref = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                                found.append(VideoFeedItem(
                                    messageId: message.id,
                                    timestamp: message.timestamp,
                                    peer: enginePeer,
                                    peerTitle: peerTitle,
                                    caption: message.text.isEmpty ? "Видео из «\(peerTitle)» (свайп вверх → следующее)" : message.text,
                                    resource: file.resource,
                                    reference: ref
                                ))
                                break
                            }
                        }
                        return found.count < 240
                    }
                }
            }
            found.sort { $0.timestamp > $1.timestamp }
            return Array(found.prefix(80))
        }

        self.searchDisposable?.dispose()
        self.searchDisposable = (localSignal
        |> deliverOnMainQueue).start(next: { [weak self] localItems in
            guard let self = self else { return }
            if !localItems.isEmpty {
                self.spinner.stopAnimating()
                self.videoItems = localItems
                self.currentIndex = 0
                self.displayCurrentVideo()
                return
            }
            let fallback = self.context.engine.messages.searchMessages(
                location: .general(scope: .everywhere, groupId: nil, tags: .video, minDate: nil, maxDate: nil, folderId: nil, communityId: nil),
                query: "",
                state: nil,
                limit: 40
            )
            self.searchDisposable = (fallback
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] result, _ in
                guard let self = self else { return }
                self.spinner.stopAnimating()
                var items: [VideoFeedItem] = []
                for message in result.messages {
                    let rawPeer = message.peers[message.id.peerId]
                    let peerTitle = rawPeer?.debugDisplayTitle ?? "Канал"
                    var fileRes: MediaResource?
                    var fileRef: MediaResourceReference?
                    for media in message.media {
                        if let file = media as? TelegramMediaFile,
                           (file.isVideo || file.isInstantVideo),
                           !file.isAnimated,
                           !file.isSticker {
                            fileRes = file.resource
                            fileRef = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                            break
                        }
                    }
                    guard fileRes != nil else { continue }
                    items.append(VideoFeedItem(
                        messageId: message.id,
                        timestamp: message.timestamp,
                        peer: rawPeer.map(EnginePeer.init),
                        peerTitle: peerTitle,
                        caption: message.text.isEmpty ? "Видео из «\(peerTitle)» (свайп вверх → следующее)" : message.text,
                        resource: fileRes,
                        reference: fileRef
                    ))
                }
                if items.isEmpty {
                    items.append(VideoFeedItem(
                        messageId: MessageId(peerId: self.context.account.peerId, namespace: 0, id: 1),
                        timestamp: 0,
                        peer: nil,
                        peerTitle: "MediaTok Feed",
                        caption: "Видео пока не загружены в чатах. Откройте любой канал с видео — и лента сразу подхватит ролики!",
                        resource: nil,
                        reference: nil
                    ))
                }
                self.videoItems = items
                self.currentIndex = 0
                self.displayCurrentVideo()
            })
        })
    }

    private func displayCurrentVideo() {
        guard !self.videoItems.isEmpty, self.currentIndex >= 0, self.currentIndex < self.videoItems.count else { return }
        let item = self.videoItems[self.currentIndex]
        self.channelLabel.text = item.peerTitle
        self.captionLabel.text = item.caption
        self.counterLabel.text = "\(self.currentIndex + 1) / \(self.videoItems.count)"

        self.fetchDisposable?.dispose()
        self.fetchDisposable = nil
        self.mediaDisposable?.dispose()
        self.mediaDisposable = nil
        if let obs = self.endObserver {
            NotificationCenter.default.removeObserver(obs)
            self.endObserver = nil
        }
        self.player?.pause()
        self.player?.replaceCurrentItem(with: nil)
        self.playerLayer?.removeFromSuperlayer()
        self.player = nil
        self.playerLayer = nil

        guard let resource = item.resource else { return }
        if let completedPath = self.context.account.postbox.mediaBox.completedResourcePath(resource) {
            self.spinner.stopAnimating()
            self.playLocalVideo(at: URL(fileURLWithPath: completedPath))
            return
        }

        self.spinner.startAnimating()
        let ref = item.reference ?? .standalone(resource: resource)
        let fetchSignal = fetchedMediaResource(mediaBox: self.context.account.postbox.mediaBox, userLocation: .peer(item.messageId.peerId), userContentType: .video, reference: ref)
        let dataSignal = self.context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)

        self.fetchDisposable = fetchSignal.start()
        self.mediaDisposable = (dataSignal |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.playLocalVideo(at: URL(fileURLWithPath: data.path))
        })
    }

    private func playLocalVideo(at sourceURL: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        if let oldTemp = self.activeTempVideoURL {
            try? FileManager.default.removeItem(at: oldTemp)
            self.activeTempVideoURL = nil
        }

        // AVPlayer on iOS refuses extensionless Telegram MediaBox cache paths; provide a .mp4 link.
        let playableURL: URL
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "mp4" || ext == "mov" || ext == "m4v" {
            playableURL = sourceURL
        } else {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mt_tt_\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: tempURL)
            if (try? FileManager.default.linkItem(at: sourceURL, to: tempURL)) != nil
                || (try? FileManager.default.createSymbolicLink(at: tempURL, withDestinationURL: sourceURL)) != nil
                || (try? FileManager.default.copyItem(at: sourceURL, to: tempURL)) != nil {
                self.activeTempVideoURL = tempURL
                playableURL = tempURL
            } else {
                playableURL = sourceURL
            }
        }

        let p = AVPlayer(url: playableURL)
        p.isMuted = self.isMuted
        let layer = AVPlayerLayer(player: p)
        layer.frame = self.videoContainer.bounds
        layer.videoGravity = .resizeAspectFill
        self.videoContainer.layer.addSublayer(layer)
        self.player = p
        self.playerLayer = layer
        p.play()
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer?.frame = self.videoContainer.bounds
    }

    @objc private func handleSwipeUp() {
        if self.currentIndex < self.videoItems.count - 1 {
            self.currentIndex += 1
            self.displayCurrentVideo()
        }
    }

    @objc private func handleSwipeDown() {
        if self.currentIndex > 0 {
            self.currentIndex -= 1
            self.displayCurrentVideo()
        }
    }

    @objc private func handleSingleTap() {
        guard let p = self.player else { return }
        if p.rate > 0 {
            p.pause()
        } else {
            p.play()
        }
    }

    @objc private func handleDoubleTap() {
        self.likeTapped()
        self.heartOverlay.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        self.heartOverlay.alpha = 1.0
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.0, options: [], animations: {
            self.heartOverlay.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0.2, options: [], animations: {
                self.heartOverlay.alpha = 0.0
            }, completion: nil)
        }
    }

    @objc private func likeTapped() {
        self.likeButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.2) {
            self.likeButton.transform = .identity
        }
    }

    @objc private func channelTapped() {
        guard self.currentIndex >= 0, self.currentIndex < self.videoItems.count else { return }
        let item = self.videoItems[self.currentIndex]
        guard let peer = item.peer, let nav = self.hostNavigationController else {
            self.dismiss(animated: true)
            return
        }
        let ctx = self.context
        let msgId = item.messageId
        self.dismiss(animated: true) {
            ctx.sharedContext.navigateToChatController(NavigateToChatControllerParams(
                navigationController: nav,
                context: ctx,
                chatLocation: .peer(peer),
                subject: .message(id: .id(msgId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false),
                keepStack: .always,
                useExisting: true
            ))
        }
    }

    @objc private func muteTapped() {
        self.isMuted.toggle()
        self.player?.isMuted = self.isMuted
        self.muteButton.setTitle(self.isMuted ? "🔇" : "🔊", for: .normal)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}
