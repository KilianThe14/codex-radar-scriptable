import Foundation
import OSLog

struct RadarLeader: Codable, Equatable, Sendable {
    let model: String
    let effort: String
    let score: String
    let cost: String
}

struct RadarSnapshot: Codable, Equatable, Sendable {
    let leaders: [RadarLeader]
    let fetchedAt: Date?

    static let preview = RadarSnapshot(leaders: [
        RadarLeader(model: "GPT-6.2 Astra", effort: "max", score: "137.18", cost: "$7.77"),
        RadarLeader(model: "GPT-6 Astra", effort: "max", score: "137.18", cost: "$5.44"),
        RadarLeader(model: "GPT-6.1 Sol", effort: "xhigh", score: "136.95", cost: "$1.06"),
        RadarLeader(model: "GPT-6.1 Terra", effort: "max", score: "133.88", cost: "$0.57")
    ], fetchedAt: nil)
}

enum RadarData {
    static let widgetKind = "CodexRadar"
    static let endpoint = URL(string: "https://codexradar.com/data/codex-four-task-summary.json")!
    static let interval: TimeInterval = 2 * 60 * 60
    static let retryInterval: TimeInterval = 30 * 60
    static let locale = Locale(identifier: "en_US_POSIX")

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    static func validLCDScore(_ text: String) -> Bool {
        text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    static func leaders(from data: Data) throws -> [RadarLeader] {
        let rows = try JSONDecoder().decode(Summary.self, from: data).rows
        var order: [String: Int] = [:]
        var best: [String: RankedRow] = [:]
        for (index, row) in rows.enumerated() {
            guard let model = row.model, !model.isEmpty else { continue }
            if order[model] == nil { order[model] = index }
            guard let score = row.score, score.isFinite,
                  let effort = row.effort, !effort.isEmpty else { continue }
            if let incumbent = best[model], incumbent.score >= score { continue }
            best[model] = RankedRow(
                order: order[model] ?? index,
                score: score,
                leader: RadarLeader(model: displayName(model), effort: effort,
                                    score: displayScore(row.scoreDisplay, raw: score),
                                    cost: displayCost(row.cost))
            )
        }
        let leaders = best.values.sorted {
            $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score
        }.prefix(4).map(\.leader)
        guard !leaders.isEmpty else { throw LoadError.noScores }
        return leaders
    }

    private static func displayName(_ model: String) -> String {
        let parts = model.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].lowercased() == "gpt",
              parts[1].range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil,
              !parts[2].isEmpty else { return model }
        let name = parts[2].split(separator: "-", omittingEmptySubsequences: false).map {
            $0.prefix(1).uppercased() + $0.dropFirst()
        }.joined(separator: " ")
        return "GPT-\(parts[1]) \(name)"
    }

    private static func displayScore(_ value: String?, raw: Double) -> String {
        if let value, validLCDScore(value) { return value }
        return String(format: "%.2f", locale: locale, raw)
    }

    private static func displayCost(_ cost: Double?) -> String {
        guard let cost, cost.isFinite, cost >= 0 else { return "—" }
        return "$" + String(format: cost >= 0.1 ? "%.2f" : "%.2g", locale: locale, cost)
    }

    private struct Summary: Decodable {
        let rows: [SourceRow]
    }

    private struct SourceRow: Decodable {
        let model: String?
        let effort: String?
        let score: Double?
        let scoreDisplay: String?
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case model, effort
            case score = "score150"
            case scoreDisplay = "score_display"
            case cost = "cost_usd"
        }

        init(from decoder: Decoder) throws {
            let row = try? decoder.container(keyedBy: CodingKeys.self)
            model = try? row?.decode(String.self, forKey: .model)
            effort = try? row?.decode(String.self, forKey: .effort)
            score = try? row?.decode(Double.self, forKey: .score)
            if let displayed = try? row?.decode(String.self, forKey: .scoreDisplay) {
                scoreDisplay = displayed
            } else if let number = try? row?.decode(Double.self, forKey: .scoreDisplay) {
                scoreDisplay = NSNumber(value: number).stringValue
            } else {
                scoreDisplay = nil
            }
            cost = try? row?.decode(Double.self, forKey: .cost)
        }
    }

    private struct RankedRow {
        let order: Int
        let score: Double
        let leader: RadarLeader
    }

    enum LoadError: Error {
        case badResponse
        case noScores
    }
}

struct RadarLoad: Sendable {
    let snapshot: RadarSnapshot?
    let successful: Bool

    var reloadAfter: TimeInterval { successful ? RadarData.interval : RadarData.retryInterval }
}

actor RadarStore {
    static let shared = RadarStore()

    private let endpoint: URL
    private let cache: URL
    private let logger = Logger(subsystem: "local.codexradar.desktop", category: "Data")
    private var inFlight: Task<RadarLoad, Never>?

    init(endpoint: URL = RadarData.endpoint, cache: URL? = nil) {
        self.endpoint = endpoint
        let parent = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cache = cache ?? parent.appendingPathComponent("CodexRadar", isDirectory: true)
            .appendingPathComponent("ranking.json")
    }

    func cached() -> RadarSnapshot? {
        guard let data = try? Data(contentsOf: cache),
              let snapshot = try? JSONDecoder().decode(RadarSnapshot.self, from: data),
              let fetchedAt = snapshot.fetchedAt, fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              (1...4).contains(snapshot.leaders.count),
              snapshot.leaders.allSatisfy({
                  !$0.model.isEmpty && !$0.effort.isEmpty && !$0.score.isEmpty && !$0.cost.isEmpty
              }) else { return nil }
        return snapshot
    }

    func refresh() async -> RadarLoad {
        if let inFlight { return await inFlight.value }
        let task = Task { await Self.fetch(endpoint: endpoint, cache: cache, fallback: cached(), logger: logger) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private static func fetch(endpoint: URL, cache: URL, fallback: RadarSnapshot?, logger: Logger) async -> RadarLoad {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw RadarData.LoadError.badResponse
            }
            let snapshot = RadarSnapshot(leaders: try RadarData.leaders(from: data), fetchedAt: Date())
            do {
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: cache, options: .atomic)
            } catch {
                logger.error("Unable to cache ranking")
            }
            return RadarLoad(snapshot: snapshot, successful: true)
        } catch {
            logger.error("Ranking request failed")
            return RadarLoad(snapshot: fallback, successful: false)
        }
    }
}
