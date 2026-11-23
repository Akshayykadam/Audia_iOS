import Foundation

let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

let body: [String: Any] = [
    "context": [
        "client": [
            "clientName": "WEB_REMIX",
            "clientVersion": "1.20240101.01.00",
            "hl": "en",
            "gl": "US"
        ]
    ],
    "browseId": "FEmusic_home"
]
request.httpBody = try! JSONSerialization.data(withJSONObject: body)

let semaphore = DispatchSemaphore(value: 0)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("Failed to get json")
        return
    }
    
    // Find continuation token
    func findContinuation(obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            if let token = dict["continuation"] as? String {
                return token
            }
            if let token = dict["continuationCommand"] as? [String: Any], let t = token["token"] as? String {
                return t
            }
            for (_, v) in dict {
                if let t = findContinuation(obj: v) { return t }
            }
        } else if let arr = obj as? [Any] {
            for v in arr {
                if let t = findContinuation(obj: v) { return t }
            }
        }
        return nil
    }

    guard let continuation = findContinuation(obj: json) else {
        print("No continuation found")
        return
    }
    print("Found continuation token:", continuation.prefix(30))

    var contReq = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/browse?continuation=\(continuation)&prettyPrint=false")!)
    contReq.httpMethod = "POST"
    contReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    contReq.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    contReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
    let contBody: [String: Any] = [
        "context": [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20240101.01.00",
                "hl": "en",
                "gl": "US"
            ]
        ]
    ]
    contReq.httpBody = try! JSONSerialization.data(withJSONObject: contBody)

    let sem2 = DispatchSemaphore(value: 0)
    let task2 = URLSession.shared.dataTask(with: contReq) { data2, resp2, err2 in
        defer { sem2.signal() }
        guard let data2 = data2, let json2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
            print("Failed continuation response")
            return
        }
        func findTitles(obj: Any) {
            if let dict = obj as? [String: Any] {
                if let title = dict["title"] as? [String: Any],
                   let runs = title["runs"] as? [[String: Any]] {
                    let t = runs.compactMap { $0["text"] as? String }.joined()
                    print("Continuation section title:", t)
                }
                for (_, v) in dict {
                    findTitles(obj: v)
                }
            } else if let arr = obj as? [Any] {
                for v in arr {
                    findTitles(obj: v)
                }
            }
        }
        findTitles(obj: json2)
    }
    task2.resume()
    sem2.wait()
}
task.resume()
semaphore.wait()
