//
//  ShareViewController.swift
//  AudiaShareExtension
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let openButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupUI()
        processSharedItems()
    }

    private func setupUI() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor(red: 18/255, green: 18/255, blue: 18/255, alpha: 0.95)
        containerView.layer.cornerRadius = 20
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        containerView.clipsToBounds = true
        view.addSubview(containerView)

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "play.circle.fill")
        iconView.tintColor = UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)
        iconView.contentMode = .scaleAspectFit
        containerView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Audia"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        containerView.addSubview(titleLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Opening link..."
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        containerView.addSubview(statusLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        containerView.addSubview(spinner)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.setTitle("Open in Audia", for: .normal)
        openButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        openButton.backgroundColor = UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)
        openButton.setTitleColor(.white, for: .normal)
        openButton.layer.cornerRadius = 14
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(didTapOpenManual), for: .touchUpInside)
        containerView.addSubview(openButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),
            containerView.heightAnchor.constraint(equalToConstant: 160),

            iconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            spinner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            openButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            openButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            openButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            openButton.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private var targetURL: URL?

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let item = extensionContext.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            dismissExtension()
            return
        }

        // Try to find a URL attachment first
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            self?.handleFoundURL(url)
                        }
                    }
                }
                return
            }
        }

        // Try text attachment (e.g. copied text containing a link)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                    if let text = item as? String,
                       let extracted = self?.extractURL(from: text) {
                        DispatchQueue.main.async {
                            self?.handleFoundURL(extracted)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.dismissExtension()
                        }
                    }
                }
                return
            }
        }

        dismissExtension()
    }

    private func extractURL(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil {
            return url
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
        return matches?.first?.url
    }

    private func handleFoundURL(_ url: URL) {
        let audiaScheme = "audia://open?url=" + (url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        guard let launchURL = URL(string: audiaScheme) else {
            dismissExtension()
            return
        }

        self.targetURL = launchURL
        openHostApp(url: launchURL)
    }

    private func openHostApp(url: URL) {
        // Method 1: Try via extensionContext selector (supported on iOS 14-17)
        var responder: UIResponder? = self
        let openSelector = sel_registerName("openURL:completionHandler:")
        while responder != nil {
            if responder?.responds(to: openSelector) == true {
                responder?.perform(openSelector, with: url, with: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.dismissExtension()
                }
                return
            }
            responder = responder?.next
        }

        // Method 2: Try via UIApplication selector
        let sharedSelector = sel_registerName("sharedApplication")
        if let uiAppClass = NSClassFromString("UIApplication") as? NSObject.Type,
           uiAppClass.responds(to: sharedSelector),
           let app = uiAppClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject {
            let appOpenSelector = sel_registerName("openURL:")
            if app.responds(to: appOpenSelector) {
                app.perform(appOpenSelector, with: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.dismissExtension()
                }
                return
            }
        }

        // Fallback: Show manual open button
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.text = "Ready to play"
        openButton.isHidden = false
    }

    @objc private func didTapOpenManual() {
        if let url = targetURL {
            openHostApp(url: url)
        }
        dismissExtension()
    }

    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
