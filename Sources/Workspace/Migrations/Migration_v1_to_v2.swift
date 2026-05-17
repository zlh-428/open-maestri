import Foundation

/// 数据格式从 v1 迁移到 v2
/// v2 新增字段：portalToPortalConnections、noteToNoteConnections、crossFloorConnections、floors、drawings
struct Migration_v1_to_v2 {
    static func migrate(data: Data) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MaestriError.schemaMigrationFailed(1, 2)
        }
        dict["schemaVersion"] = 2
        if var payload = dict["payload"] as? [String: Any] {
            let arrayFields = [
                "portalToPortalConnections",
                "noteToNoteConnections",
                "crossFloorConnections",
                "floors",
                "drawings",
            ]
            for field in arrayFields {
                if payload[field] == nil { payload[field] = [] }
            }
            if payload["icon"] == nil { payload["icon"] = "folder" }
            if payload["isPinned"] == nil { payload["isPinned"] = false }
            if payload["locationType"] == nil { payload["locationType"] = "local" }
            if payload["preferredIDE"] == nil { payload["preferredIDE"] = "cursor" }
            if payload["syncConfigFiles"] == nil { payload["syncConfigFiles"] = false }
            dict["payload"] = payload
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }
}
