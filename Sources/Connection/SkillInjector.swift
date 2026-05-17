import Foundation
import OSLog

/// Skill 脚本注入器
/// 在 Terminal↔Terminal 连接建立时向两端 PTY 写入 omaestri() Shell 函数
/// Shell 函数封装 curl 调用 InterAgentServer，与 Maestri 官方 CLI 兼容
final class SkillInjector {
    static let shared = SkillInjector()
    private let logger = Logger.make(category: "SkillInjector")
    private init() {}

    // MARK: - 注入

    func inject(to terminalId: UUID, host: String) {
        let script = buildSkillScript(terminalId: terminalId, host: host)
        let id = terminalId
        Task { @MainActor in
            // 使用 write（不追加额外 "\n"）避免破坏多行脚本结构
            // 脚本本身已包含 "\n" 终止行
            TerminalManager.shared.write(to: id, text: script + "\n")
        }
        logger.debug("Skill injected to terminal \(terminalId.uuidString.prefix(8))")
    }

    // MARK: - Skill 脚本生成（与 Maestri 官方逆向完全一致）

    func buildSkillScript(terminalId: UUID, host: String) -> String {
        """
        export OMAESTRI_TERMINAL_ID="\(terminalId.uuidString)"
        export OMAESTRI_HOST="\(host)"
        export MAESTRI_TERMINAL_ID="\(terminalId.uuidString)"
        export MAESTRI_HOST="\(host)"
        json_array() {
          if command -v jq >/dev/null 2>&1; then
            printf '%s\\n' "$@" | jq -R . | jq -s .
          else
            printf '['
            local first=true
            for arg in "$@"; do
              $first || printf ','
              first=false
              printf '"%s"' "$(printf '%s' "$arg" | \\
                sed 's/\\\\/\\\\\\\\/g' | sed 's/"/\\\\"/g' | \\
                sed ':a;N;$!ba;s/\\n/\\\\n/g' | \\
                sed 's/\\t/\\\\t/g' | sed 's/\\r/\\\\r/g')"
            done
            printf ']'
          fi
        }
        omaestri() {
          curl -sf --max-time 30 \\
            -H "X-Terminal-ID:$OMAESTRI_TERMINAL_ID" \\
            -H "Content-Type:application/json" \\
            -d "{\\"args\\":$(json_array "$@")}" \\
            "http://$OMAESTRI_HOST/cli"
        }
        maestri() { omaestri "$@"; }
        echo "✅ omaestri skill ready (terminal: $OMAESTRI_TERMINAL_ID)"
        """
    }
}
