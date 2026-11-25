//
//  LyricsService.swift
//  Audia
//

import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval?
    let text: String
    var translatedText: String?
}

struct LyricsResult: Equatable, Sendable {
    var lines: [LyricLine]
    let isSynced: Bool
}

actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: LyricsResult] = [:]
    private var translationCache: [String: [Int: String]] = [:]

    func fetchLyrics(videoId: String, title: String, artist: String, duration: TimeInterval) async -> LyricsResult? {
        if let cached = cache[videoId] {
            return cached
        }

        let cleanTitle = cleanQueryTitle(title)
        let cleanArtist = cleanQueryArtist(artist)

        // 1. Exact match via LRCLIB /api/get
        if let result = await fetchLRCLibGet(title: cleanTitle, artist: cleanArtist, duration: duration) {
            cache[videoId] = result
            return result
        }

        // 2. Search fallback via LRCLIB /api/search
        let query = [cleanArtist, cleanTitle].filter { !$0.isEmpty }.joined(separator: " ")
        if !query.isEmpty, let result = await fetchLRCLibSearch(query: query, targetDuration: duration) {
            cache[videoId] = result
            return result
        }

        // 3. Title-only search fallback
        if !cleanTitle.isEmpty, cleanTitle != query,
           let result = await fetchLRCLibSearch(query: cleanTitle, targetDuration: duration) {
            cache[videoId] = result
            return result
        }

        return nil
    }

    func translateLines(videoId: String, lines: [LyricLine], targetLanguage: String? = nil) async -> [LyricLine] {
        let lang = targetLanguage ?? (Locale.current.language.languageCode?.identifier ?? "en")
        let cacheKey = "\(videoId)_\(lang)"

        if let cachedMap = translationCache[cacheKey] {
            return lines.map { line in
                var copy = line
                copy.translatedText = cachedMap[line.id]
                return copy
            }
        }

        let nonEmpty = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else { return lines }

        // Batch all lines in a single request separated by newlines
        let joined = nonEmpty.map(\.text).joined(separator: "\n")
        guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(lang)&dt=t&q=\(encoded)") else {
            return lines
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let segments = json.first as? [[Any]] else {
                return lines
            }

            let fullTranslated = segments.compactMap { $0.first as? String }.joined()
            let translatedParts = fullTranslated.components(separatedBy: "\n")

            var map: [Int: String] = [:]
            for (idx, line) in nonEmpty.enumerated() where idx < translatedParts.count {
                let translated = translatedParts[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if !translated.isEmpty && translated.caseInsensitiveCompare(line.text.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                    map[line.id] = translated
                }
            }

            translationCache[cacheKey] = map
            return lines.map { line in
                var copy = line
                copy.translatedText = map[line.id]
                return copy
            }
        } catch {
            return lines
        }
    }

    // MARK: - LRCLIB

    private func fetchLRCLibGet(title: String, artist: String, duration: TimeInterval) async -> LyricsResult? {
        guard !title.isEmpty,
              var components = URLComponents(string: "https://lrclib.net/api/get") else {
            return nil
        }
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        if duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(round(duration)))))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Audia/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return parseLRCLibRecord(dict)
        } catch {
            return nil
        }
    }

    private func fetchLRCLibSearch(query: String, targetDuration: TimeInterval) async -> LyricsResult? {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Audia/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !array.isEmpty else {
                return nil
            }

            // Prefer synced lyrics and closest duration
            let sorted = array.sorted { a, b in
                let aSynced = (a["syncedLyrics"] as? String)?.isEmpty == false
                let bSynced = (b["syncedLyrics"] as? String)?.isEmpty == false
                if aSynced != bSynced { return aSynced }
                if targetDuration > 0 {
                    let aDur = abs((a["duration"] as? Double ?? targetDuration) - targetDuration)
                    let bDur = abs((b["duration"] as? Double ?? targetDuration) - targetDuration)
                    return aDur < bDur
                }
                return false
            }

            for record in sorted {
                if let parsed = parseLRCLibRecord(record) {
                    return parsed
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func parseLRCLibRecord(_ dict: [String: Any]) -> LyricsResult? {
        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                return LyricsResult(lines: lines, isSynced: true)
            }
        }
        if let plain = dict["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rawLines = plain.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let lines = rawLines.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
            if !lines.isEmpty {
                return LyricsResult(lines: lines, isSynced: false)
            }
        }
        return nil
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var parsed: [(time: TimeInterval, text: String)] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            let lastEnd = matches.last!.range.upperBound
            let text = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let fracRange = match.range(at: 3)
                var frac: TimeInterval = 0
                if fracRange.location != NSNotFound {
                    let fracStr = nsLine.substring(with: fracRange)
                    let val = Double(fracStr) ?? 0
                    frac = fracStr.count == 3 ? val / 1000.0 : val / 100.0
                }
                let time = (Double(minStr) ?? 0) * 60.0 + (Double(secStr) ?? 0) + frac
                parsed.append((time: time, text: text))
            }
        }

        parsed.sort { $0.time < $1.time }
        return parsed.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    private func cleanQueryTitle(_ title: String) -> String {
        var cleaned = title
        let patterns = [
            #"[\(\[]\s*(?:official\s*(?:music\s*)?video|official\s*audio|lyric\s*video|lyrics?|visualizer|official|audio|video|hd|4k|remix|remastered)\s*[\)\]]"#,
            #"[\(\[]\s*(?:feat\.?|ft\.?)\s+[^\)\]]+[\)\]]"#,
            #"\|\s*.*$"#
        ]
        for p in patterns {
            cleaned = cleaned.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanQueryArtist(_ artist: String) -> String {
        let first = artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? artist
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
