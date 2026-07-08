import Foundation

// MARK: - AIModel / EffortLevel
// claude --model / --effort に渡すモデルとeffortの定義。
// id はCLIのエイリアス（opus/sonnet/haiku/fable）。

struct AIModel: Identifiable, Hashable {
    let id: String       // claude --model エイリアス
    let name: String     // 表示名
    let subtitle: String // 補足

    static let all: [AIModel] = [
        AIModel(id: "opus",   name: "Opus 4.8",  subtitle: "最も高性能"),
        AIModel(id: "sonnet", name: "Sonnet 5",  subtitle: "バランス型"),
        AIModel(id: "haiku",  name: "Haiku 4.5", subtitle: "高速・軽量"),
        AIModel(id: "fable",  name: "Fable 5",   subtitle: "Fable")
    ]

    static func named(_ id: String) -> AIModel {
        all.first { $0.id == id } ?? all[0]
    }
}

enum EffortLevel: String, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .xhigh:  return "XHigh"
        case .max:    return "Max"
        }
    }
}

/// 入力欄のモデルピル表示用（例: "Opus 4.8 High"）。
func modelPillLabel(model: String, effort: String) -> String {
    let m = AIModel.named(model).name
    let e = EffortLevel(rawValue: effort)?.label ?? effort.capitalized
    return "\(m) \(e)"
}
