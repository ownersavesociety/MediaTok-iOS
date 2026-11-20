import Foundation
import UIKit
import AVFoundation
import TelegramPresentationData
import TelegramCore
import AccountContext
import Display
import SwiftSignalKit
import GGCore
import GGHooks

/// Unified RSS / TikTok-Style Vertical Media Feed (#187)
/// Seamless full-screen vertical swipe feed for videos & video messages across all subscribed channels!
public final class GGTikTokFeedViewController: UIViewController {
    private let context: AccountContext
    private var videoItems: [VideoFeedItem] = []
    private var currentIndex: Int = 0
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let videoContainer = UIView()
    private let channelLabel = UILabel()
    private let captionLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let chatButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let heartOverlay = UIImageView()
    private var isMuted: Bool = false
    private var searchDisposable: Disposable?

    public struct VideoFeedItem {
        public let messageId: MessageId
        public let peerTitle: String
        public let caption: String
        public let dateText: String
        public let videoUrl: URL?
    }

    public init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        searchDisposable?.dispose()
        player?.pause()
        player = nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        setupUI()
        setupGestures()
        loadChannelVideos()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }

    private func setupUI() {
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.backgroundColor = .black
        self.view.addSubview(videoContainer)

        // Top bar
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "🎬 TikTok-лента каналов"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        self.view.addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        self.view.addSubview(closeButton)

        // Bottom channel & caption overlay
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        channelLabel.textColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
        channelLabel.font = .systemFont(ofSize: 17, weight: .bold)
        channelLabel.isUserInteractionEnabled = true
        let channelTap = UITapGestureRecognizer(target: self, action: #selector(channelTapped))
        channelLabel.addGestureRecognizer(channelTap)
        self.view.addSubview(channelLabel)

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.textColor = .white
        captionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        captionLabel.numberOfLines = 3
        self.view.addSubview(captionLabel)

        // Right side action buttons
        likeButton.translatesAutoresizingMaskIntoConstraints = false
        likeButton.setTitle("❤️", for: .normal)
        likeButton.titleLabel?.font = .systemFont(ofSize: 32)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        self.view.addSubview(likeButton)

        chatButton.translatesAutoresizingMaskIntoConstraints = false
        chatButton.setTitle("💬", for: .normal)
        chatButton.titleLabel?.font = .systemFont(ofSize: 30)
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)
        self.view.addSubview(chatButton)

        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.setTitle("🔊", for: .normal)
        muteButton.titleLabel?.font = .systemFont(ofSize: 28)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        self.view.addSubview(muteButton)

        heartOverlay.translatesAutoresizingMaskIntoConstraints = false
        heartOverlay.image = UIImage(systemName: "heart.fill")
        heartOverlay.tintColor = UIColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 0.9)
        heartOverlay.alpha = 0.0
        self.view.addSubview(heartOverlay)

        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: self.view.topAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            closeButton.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),

            muteButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -18),
            muteButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            muteButton.widthAnchor.constraint(equalToConstant: 48),
            muteButton.heightAnchor.constraint(equalToConstant: 48),

            chatButton.trailingAnchor.constraint(equalTo: muteButton.trailingAnchor),
            chatButton.bottomAnchor.constraint(equalTo: muteButton.topAnchor, constant: -16),
            chatButton.widthAnchor.constraint(equalToConstant: 48),
            chatButton.heightAnchor.constraint(equalToConstant: 48),

            likeButton.trailingAnchor.constraint(equalTo: chatButton.trailingAnchor),
            likeButton.bottomAnchor.constraint(equalTo: chatButton.topAnchor, constant: -16),
            likeButton.widthAnchor.constraint(equalToConstant: 48),
            likeButton.heightAnchor.constraint(equalToConstant: 48),

            captionLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 18),
            captionLabel.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -16),
            captionLabel.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            channelLabel.leadingAnchor.constraint(equalTo: captionLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: captionLabel.trailingAnchor),
            channelLabel.bottomAnchor.constraint(equalTo: captionLabel.topAnchor, constant: -8),

            heartOverlay.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            heartOverlay.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            heartOverlay.widthAnchor.constraint(equalToConstant: 120),
            heartOverlay.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func setupGestures() {
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        self.view.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        self.view.addGestureRecognizer(swipeDown)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(doubleTap)
    }

    private func loadChannelVideos() {
        let signal = self.context.engine.messages.searchMessages(
            location: .general(scope: .everywhere, groupId: nil, tags: [.video], minDate: nil, maxDate: nil, folderId: nil, communityId: nil),
            query: "",
            state: nil,
            limit: 40
        )

        searchDisposable = (signal
            |> deliverOnMainQueue).start(next: { [weak self] result, _ in
                guard let self = self else { return }
                var items: [VideoFeedItem] = []
                for message in result.messages {
                    let peer = message.peers[message.id.peerId]
                    let peerTitle = peer?.displayTitle(strings: nil, displayOrder: .firstLast) ?? "Канал"
                    var videoUrl: URL? = nil
                    for media in message.media {
                        if let file = media as? TelegramMediaFile, file.isVideo {
                            let path = self.context.account.postbox.mediaBox.resourcePath(file.resource)
                            if FileManager.default.fileExists(atPath: path) {
                                videoUrl = URL(fileURLWithPath: path)
                            }
                        }
                    }
                    items.append(VideoFeedItem(
                        messageId: message.id,
                        peerTitle: peerTitle,
                        caption: message.text.isEmpty ? "Видеозапись" : message.text,
                        dateText: "",
                        videoUrl: videoUrl
                    ))
                }

                if items.isEmpty {
                    items.append(VideoFeedItem(
                        messageId: MessageId(peerId: self.context.account.peerId, namespace: 0, id: 1),
                        peerTitle: "MediaTok Channel",
                        caption: "Добро пожаловать в TikTok-ленту каналов MediaTok! Подпишитесь на каналы с видео для просмотра ленты.",
                        dateText: "",
                        videoUrl: nil
                    ))
                }
                self.videoItems = items
                self.displayCurrentVideo()
            })
    }

    private func displayCurrentVideo() {
        guard !videoItems.isEmpty && currentIndex >= 0 && currentIndex < videoItems.count else { return }
        let item = videoItems[currentIndex]
        channelLabel.text = "📢 \(item.peerTitle)"
        captionLabel.text = item.caption

        player?.pause()
        playerLayer?.removeFromSuperlayer()

        if let url = item.videoUrl {
            let p = AVPlayer(url: url)
            p.isMuted = self.isMuted
            let layer = AVPlayerLayer(player: p)
            layer.frame = videoContainer.bounds
            layer.videoGravity = .resizeAspectFill
            videoContainer.layer.addSublayer(layer)
            self.player = p
            self.playerLayer = layer
            p.play()
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoContainer.bounds
    }

    @objc private func handleSwipeUp() {
        if currentIndex < videoItems.count - 1 {
            currentIndex += 1
            displayCurrentVideo()
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }
    }

    @objc private func handleSwipeDown() {
        if currentIndex > 0 {
            currentIndex -= 1
            displayCurrentVideo()
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }
    }

    @objc private func handleDoubleTap() {
        likeTapped()
        heartOverlay.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        heartOverlay.alpha = 1.0
        UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.0, options: [], animations: {
            self.heartOverlay.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.2, options: [], animations: {
                self.heartOverlay.alpha = 0.0
            }, completion: nil)
        }
    }

    @objc private func likeTapped() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        likeButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.2) {
            self.likeButton.transform = .identity
        }
    }

    @objc private func chatTapped() {
        channelTapped()
    }

    @objc private func channelTapped() {
        guard currentIndex >= 0 && currentIndex < videoItems.count else { return }
        let item = videoItems[currentIndex]
        let peerId = item.messageId.peerId
        self.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
                navigationController: nil,
                context: self.context,
                chatLocation: .peer(id: peerId)
            ))
        }
    }

    @objc private func muteTapped() {
        isMuted.toggle()
        player?.isMuted = isMuted
        muteButton.setTitle(isMuted ? "🔇" : "🔊", for: .normal)
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }
}
