//
//  AsyncImageView.swift
//  Audia
//

import Nuke
import SwiftUI

struct AsyncImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var targetSize: CGSize? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?

    init(url: String?, contentMode: ContentMode = .fill, targetSize: CGSize? = nil) {
        self.url = url
        self.contentMode = contentMode
        self.targetSize = targetSize
        if let urlString = url, !urlString.hasPrefix("localcover://") {
            let preferred = normalizeThumbnailURL(urlString, pixels: 720)
            let hiRes = normalizeThumbnailURL(urlString, pixels: 1200)
            if let u1200 = URL(string: hiRes), let cached = ArtworkLoader.cachedImage(for: u1200) {
                _loadedImage = State(initialValue: cached)
            } else if let u720 = URL(string: preferred), let cached = ArtworkLoader.cachedImage(for: u720) {
                _loadedImage = State(initialValue: cached)
            }
        }
    }

    var body: some View {
        if let target = targetSize {
            content(size: target)
                .frame(width: target.width, height: target.height)
                .task(id: url) {
                    await loadImage(targetSize: target)
                }
        } else {
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                let taskId = "\(url ?? "")_\(Int(w / 24))x\(Int(h / 24))"
                content(size: geometry.size)
                    .task(id: taskId) {
                        guard w > 1, h > 1 else { return }
                        await loadImage(targetSize: geometry.size)
                    }
            }
        }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let image = loadedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()
                .transition(.opacity)
        } else {
            placeholderView
        }
    }

    private func loadImage(targetSize: CGSize) async {
        guard let urlString = url else {
            loadedImage = nil
            return
        }
        let maxPt = max(targetSize.width, targetSize.height)
        let resolvedURL: URL?
        if urlString.hasPrefix("localcover://") {
            let filename = String(urlString.dropFirst("localcover://".count))
            resolvedURL = PlaylistCoverStorage.url(for: filename)
        } else {
            let rung = maxPt > 160 ? 1200 : 720
            let normalized = normalizeThumbnailURL(urlString, pixels: rung)
            resolvedURL = URL(string: normalized)
        }
        guard let url = resolvedURL else {
            loadedImage = nil
            return
        }
        let request = ImageRequest(url: url)
        do {
            let image = try await ImagePipeline.shared.image(for: request)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                loadedImage = image
            }
        } catch {
            guard !Task.isCancelled else { return }
            loadedImage = nil
        }
    }

    private var placeholderView: some View {
        Image(systemName: "music.note")
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }
}

enum PlaylistCoverStorage {
    static let scheme = "localcover://"

    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("PlaylistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL? {
        directory?.appendingPathComponent(filename)
    }

    static func save(imageData: Data, playlistId: String, previousUrl: String?) -> String? {
        guard let dir = directory, let image = UIImage(data: imageData) else { return nil }
        // Downscale very large photos to max 1200px on longest edge
        let maxDim: CGFloat = 1200
        let size = image.size
        let scaled: UIImage
        if max(size.width, size.height) > maxDim {
            let ratio = maxDim / max(size.width, size.height)
            let target = CGSize(width: size.width * ratio, height: size.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: target)
            scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        } else {
            scaled = image
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.88) else { return nil }

        if let prev = previousUrl {
            delete(urlString: prev)
        }

        let filename = "\(playlistId)_\(UUID().uuidString.prefix(8)).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return "\(scheme)\(filename)"
        } catch {
            return nil
        }
    }

    static func delete(urlString: String?) {
        guard let urlString, urlString.hasPrefix(scheme), let dir = directory else { return }
        let filename = String(urlString.dropFirst(scheme.count))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    }
}

private func normalizeThumbnailURL(_ urlString: String, pixels: Int) -> String {
    var url = urlString

    url = url.replacingOccurrences(of: "(?<=[sh]\\d+)-c", with: "", options: .regularExpression)

    if url.contains("googleusercontent.com") || url.contains("ggpht.com") {
        if let match = try? NSRegularExpression(pattern: "w(\\d+)-h(\\d+)"),
           let result = match.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let wRange = Range(result.range(at: 1), in: url),
           let hRange = Range(result.range(at: 2), in: url),
           let w = Int(url[wRange]),
           let h = Int(url[hRange]) {
            let size = "w\(pixels)-h\(pixels)"
            if size != "w\(w)-h\(h)" {
                url = url.replacingOccurrences(of: "w\(w)-h\(h)", with: size)
            }
        } else if let base = url.split(separator: "=").first {
            // Bare CDN URL with no size params: pin an explicit size instead
            // of trusting the server default.
            url = String(base) + "=w\(pixels)-h\(pixels)"
        }
    }

    if url.contains("i.ytimg.com/vi/") {
        let base = url.split(separator: "?").first.map(String.init) ?? url
        let targetFile = pixels >= 800 ? "sddefault.jpg" : "hqdefault.jpg"
        let lowResVariants = pixels >= 800
            ? ["default.jpg", "mqdefault.jpg", "hqdefault.jpg"]
            : ["default.jpg", "mqdefault.jpg"]
        for lowRes in lowResVariants {
            if base.hasSuffix("/\(lowRes)") {
                url = base.replacingOccurrences(of: "/\(lowRes)", with: "/\(targetFile)")
                break
            }
        }
    }

    return url
}
