import XCTest
@testable import open_maestri

final class MigrationTests: XCTestCase {

    func testMigration_v1_to_v2_setsSchemaVersion() throws {
        let v1Json = """
        {
          "schemaVersion": 1,
          "type": "workspace",
          "payload": {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Old",
            "nodes": [],
            "connections": [],
            "noteConnections": [],
            "portalConnections": [],
            "canvasOrigin": {"x": 9800, "y": 8500},
            "canvasZoom": 1.0,
            "workingDirectory": "/tmp",
            "createdAt": "2026-01-01T00:00:00Z",
            "lastModifiedAt": "2026-01-01T00:00:00Z"
          }
        }
        """
        let data = Data(v1Json.utf8)
        let migrated = try Migration_v1_to_v2.migrate(data: data)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        XCTAssertEqual(dict["schemaVersion"] as? Int, 2)
    }

    func testMigration_v1_to_v2_addsPortalToPortalConnections() throws {
        let v1Json = """
        {
          "schemaVersion": 1,
          "type": "workspace",
          "payload": {
            "id": "00000000-0000-0000-0000-000000000002",
            "name": "Old",
            "nodes": [],
            "connections": [],
            "noteConnections": [],
            "portalConnections": [],
            "canvasOrigin": {"x": 9800, "y": 8500},
            "canvasZoom": 1.0,
            "workingDirectory": "/tmp",
            "createdAt": "2026-01-01T00:00:00Z",
            "lastModifiedAt": "2026-01-01T00:00:00Z"
          }
        }
        """
        let data = Data(v1Json.utf8)
        let migrated = try Migration_v1_to_v2.migrate(data: data)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        let payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        XCTAssertNotNil(payload["portalToPortalConnections"])
    }
}
