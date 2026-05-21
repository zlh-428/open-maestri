// Sources/Connection/SkillInjector.swift
import Foundation
import OSLog

/// 将 open-maestri skill 文件写入用户全局 ~/.claude/skills/ 目录
/// 在建立 Connection 时调用，确保 Claude Code 能自动加载 omaestri 相关 skill
final class SkillInjector {
    static let shared = SkillInjector()
    private let logger = Logger.make(category: "SkillInjector")
    private init() {}

    // MARK: - 写入 skill 文件

    func inject(to terminalId: UUID, host: String) {
        // no-op: skill 写入已在 applicationDidFinishLaunching 完成
    }

    /// 按需写入：skill 文件不存在时写入，已存在则跳过（用户可自行编辑）
    func installSkillsIfNeeded() {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let skillsRoot = "\(homeDir)/.claude/skills"

        for skill in Self.skills {
            let dir = "\(skillsRoot)/\(skill.name)"
            let file = "\(dir)/SKILL.md"
            guard !fm.fileExists(atPath: file) else {
                logger.debug("SkillInjector: '\(skill.name)' already exists, skipping")
                continue
            }
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try skill.content.write(toFile: file, atomically: true, encoding: .utf8)
                logger.info("SkillInjector: installed skill '\(skill.name)'")
            } catch {
                logger.error("SkillInjector: failed to write '\(skill.name)': \(error)")
            }
        }
    }

    // MARK: - Skill 内容

    private struct SkillFile {
        let name: String
        let content: String
    }

    private static let skills: [SkillFile] = [
        SkillFile(name: "open-maestri", content: skillOpenMaestri),
        SkillFile(name: "open-maestri-portal", content: skillOpenMaestriPortal),
        SkillFile(name: "open-maestri-manager", content: skillOpenMaestriManager),
    ]

    // MARK: open-maestri

    private static let skillOpenMaestri = """
    ---
    name: open-maestri
    description: Send messages to connected AI agents on the open-maestri canvas and get their responses. Also read and write connected sticky notes. Use when the user's intent is to collaborate with another agent on the canvas. Look for actions like 'ask [name] to...', 'tell [name] to...', 'check on [name]', or 'create/update a note'.
    user-invocable: false
    ---

    # open-maestri Inter-Agent Communication

    You're running inside open-maestri, a spatial workspace with other coding agents and sticky notes nearby.
    Connected agents can exchange prompts and responses through the `omaestri` CLI.
    Connected notes can be read and written through the `omaestri` CLI.

    ## Commands

    - `omaestri list`
      list connected agents, notes, and portals

    - `omaestri ask "Agent Name" "your prompt"`
      send a prompt to a connected agent and get the response

    - `omaestri check "Agent Name" [lines]`
      read the agent's current terminal output on demand (default 20 lines)

    - `omaestri note create ["content"]`
      create a new note on the canvas and link it to this terminal

    - `omaestri note read "Note Name"`
      read the full note with line numbers

    - `omaestri note read "Note Name" 10 20`
      read 20 lines starting from line 10

    - `omaestri note write "Note Name" "content"`
      replace a note's content entirely

    - `omaestri note edit "Note Name" "old text" "new text"`
      replace a substring within a note

    The `omaestri` CLI is pre-installed and available on PATH inside open-maestri terminals.
    If `omaestri` is not found on PATH (e.g., custom shell setups that reset PATH), use `"$MAESTRI_CLI"` instead — this environment variable always points to the full binary path.

    Always run `omaestri list` first to get the exact agent and note names.

    The response from `ask` returns as soon as the other agent finishes. Scale the Bash tool timeout to the estimated completion time:

    - **60000ms** (1 min) — quick questions, status checks, simple lookups
    - **300000ms** (5 min) — delegating a small, focused task (a single file change, a quick refactor)
    - **600000ms** (10 min) — code reviews, multi-step tasks, larger delegations
    - **1200000ms** (20 min) — debugging sessions, complex investigations, multi-file refactors

    If the timeout expires before the agent responds, do NOT re-send the prompt. Run `omaestri check "Agent Name"` to see their progress, then wait again with an appropriate timeout. Never interrupt an agent that is still working, and do not edit files that the other agent is actively modifying — wait for them to finish first.

    Use `check` to read what an agent is currently showing without sending a prompt — useful to check if a previous request completed or to see its current state.

    Run `omaestri debug` to diagnose connection or setup issues.

    ## Connected Notes

    Use `omaestri note create` to create a new note on the canvas — it appears linked to your terminal and is automatically connected. Optional initial content can be provided.

    Notes support line-range reads: `omaestri note read "Note Name" <offset> <limit>` where offset is the starting line number and limit is how many lines to return.

    Use `omaestri note write` to replace the entire note content. Use `omaestri note edit` for surgical in-place replacements.
    """

    // MARK: open-maestri-portal

    private static let skillOpenMaestriPortal = """
    ---
    name: open-maestri-portal
    description: Use a browser portal on the open-maestri canvas to navigate the web, interact with pages, fill forms, and inspect content. Use when the user asks to browse a URL, test a web UI, or interact with a website.
    user-invocable: false
    ---

    # open-maestri Portal Browser Automation

    Portals are embedded browser nodes on the open-maestri canvas. You can automate them to navigate pages, click elements, fill forms, take screenshots, and inspect the DOM — all without requiring window focus.

    Portal name is always required. Run `omaestri list` to see connected portal names.

    ## Creating a portal

    `omaestri portal create "URL" ["Name"]`
    create a new portal on the canvas, open it at the given URL, and automatically connect it to your terminal. An optional name can be provided; if omitted it defaults to `Portal-<id>`.

    ```
    omaestri portal create http://localhost:3000
    omaestri portal create https://example.com "Docs"
    ```

    After creating, run `omaestri list` to confirm the portal name, then use it with all other portal commands.

    ## Navigation

    `omaestri portal navigate "Portal Name" "URL"`
    navigate the portal to a new URL.

    `omaestri portal edit "Portal Name" --url "URL"`
    update the portal's URL (alias for navigate).

    ## Inspection

    `omaestri portal info "Portal Name"`
    get the current URL, page title, and viewport size.

    `omaestri portal snapshot "Portal Name"`
    get the accessibility tree — a structured, concise view of interactive elements.
    **Start here.** The snapshot shows element references like `@e1`, `@e2` that you use in other commands.

    `omaestri portal screenshot "Portal Name"`
    capture a base64-encoded PNG of the current page.

    `omaestri portal html "Portal Name"`
    get the full outer HTML of the page.

    `omaestri portal text "Portal Name" @e1`
    get the text content of a specific element (by `@eN` reference or CSS selector).

    ## Interaction

    Element references use the `@eN` format from `snapshot`, or CSS selectors directly.

    `omaestri portal click "Portal Name" @e1`
    click an element by reference or CSS selector. Also supports coordinate pairs: `omaestri portal click "Portal" "120,340"`.

    `omaestri portal fill "Portal Name" @e1 "value"`
    set the value of an input/textarea/select and fire change events.

    `omaestri portal type "Portal Name" "text"`
    append text to the currently focused element.

    `omaestri portal key "Portal Name" "Enter"`
    dispatch a keyboard event (e.g., `Enter`, `Escape`, `Tab`, `ArrowDown`) to the focused element.

    `omaestri portal hover "Portal Name" @e1`
    trigger mouseover/mouseenter events on an element.

    `omaestri portal scroll "Portal Name" down [amount]`
    scroll the page. Direction: `up` | `down` | `left` | `right`. Amount defaults to 300px.

    `omaestri portal drag "Portal Name" @e1 @e2`
    drag from one element to another using mouse events.

    `omaestri portal wait "Portal Name" @e1 [timeoutMs]`
    wait for an element to appear in the DOM. Timeout defaults to 5000ms.

    `omaestri portal evaluate "Portal Name" "javascript"`
    execute arbitrary JavaScript and return the result.

    ## Workflow

    1. Run `omaestri portal snapshot "Portal Name"` to see the page structure and element references.
    2. Use `@eN` references from the snapshot in `click`, `fill`, `text`, etc.
    3. After interactions, run `snapshot` again to verify the page updated as expected.
    4. Use `screenshot` when you need visual confirmation.
    """

    // MARK: open-maestri-manager

    private static let skillOpenMaestriManager = """
    ---
    name: open-maestri-manager
    description: Create new connected agent terminals on the open-maestri canvas and assign them roles. Use when the user asks to assemble a team, delegate parallel work, or spin up additional agents or terminals to help, or to invoke Maestro Mode.
    user-invocable: false
    ---

    # open-maestri Team Orchestration

    The commands below spawn new agent terminals on the canvas, assign them roles, and wire them together.
    Recruits are auto-connected to your terminal — once a recruit exists you can `omaestri ask "Name" "..."` to delegate work and `omaestri check "Name"` to read their output.

    ## Reuse before recruiting

    **Before calling `omaestri recruit`, always run `omaestri list` first.**
    If a connected teammate already has a fitting role, delegate to them with `omaestri ask "Name" "..."` — do NOT spin up a new recruit for the same role.

    Only recruit when:
    - `omaestri list` shows nobody whose role covers the task, AND
    - the work genuinely needs a new persona (e.g. a reviewer-only voice when your existing teammate is the implementer).

    If an existing recruit's role is close but wrong, prefer `omaestri role edit` over recruiting a duplicate.

    ## Commands

    ### `omaestri recruit "Name" [--preset "Claude Code"] [--role "Reviewer"] [--command "claude"]`

    Spawn a new agent terminal on the canvas with the given name.

    - `--preset` — use a configured agent preset by name or type (e.g. `claude_code`, `codex`, `generic_shell`). Run `omaestri preset list` to see available presets.
    - `--role` — assign a role preset by name. The role's instructions are injected as system context. Run `omaestri role list` to see available roles.
    - `--command` — override the launch command directly (e.g. `claude --resume`).

    ```
    omaestri recruit "Reviewer" --preset "Claude Code" --role "Code Reviewer"
    omaestri recruit "Tester" --command "claude" --role "QA Engineer"
    omaestri recruit "Shell" --preset "generic_shell"
    ```

    After recruiting, the new terminal is auto-connected. Delegate immediately:
    ```
    omaestri ask "Reviewer" "Please review the changes in src/Auth.swift"
    ```

    ### `omaestri dismiss "Name"`

    Stop and remove a recruited agent terminal from the canvas. Disconnects it and terminates its process.

    ```
    omaestri dismiss "Reviewer"
    ```

    ### `omaestri connect "From" "To"`

    Manually wire two existing terminals together so they can communicate via `omaestri ask`.

    ```
    omaestri connect "Reviewer" "Tester"
    ```

    ### `omaestri role list`

    List all configured role presets with their instructions preview.

    ### `omaestri role create "RoleName" "Role instructions"`

    Create a new role preset saved to preferences.

    ```
    omaestri role create "Code Reviewer" "You are a meticulous code reviewer. Focus on correctness, security, and readability. Always cite the specific line or pattern you are commenting on."
    ```

    ### `omaestri role show "RoleName"`

    Show the full details (name and prompt) of a role.

    ```
    omaestri role show "Code Reviewer"
    ```

    ### `omaestri role edit "RoleName" --prompt "new instructions"`

    Update an existing role's instructions. `write` is an alias for `edit`.

    ```
    omaestri role edit "Code Reviewer" --prompt "You are a strict code reviewer focused on security vulnerabilities and performance."
    omaestri role write "Code Reviewer" --prompt "Updated instructions here."
    ```

    ### `omaestri role assign "AgentName" "RoleName"`

    Assign a role to an existing agent (takes effect on next restart). Use `--none` to clear the role.

    ```
    omaestri role assign "Reviewer" "Code Reviewer"
    omaestri role assign "Reviewer" --none
    ```

    ### `omaestri preset list`

    List all configured agent presets (Claude Code, Codex, generic shell, custom presets). Run this before `omaestri recruit --preset "..."` to confirm the preset name exists.

    ## Workflow

    1. Run `omaestri list` — check if you already have teammates who can do the job.
    2. Run `omaestri preset list` and `omaestri role list` — find the right preset and role.
    3. `omaestri recruit "Name" --preset "..." --role "..."` — spawn the agent.
    4. Wait a moment for the terminal to start (the agent needs to initialize).
    5. `omaestri ask "Name" "task description"` — delegate the work with an appropriate Bash timeout.
    6. `omaestri check "Name"` — monitor progress without interrupting.
    7. `omaestri dismiss "Name"` — clean up when the task is done.
    """
}
