# maestri list
zhoulihao@macbook ~ % maestri list
Connected agents:
  - name: "Claude Code #2"

Connected portals (use `maestri portal check`):
  - name: "公私海" - url: https://wm-ocrm.waimai.test.sankuai.com

Connected notes (use `maestri note read/write/edit`):
  - name: "note"

# maestri check "Agent Name"
zhoulihao@macbook ~ % maestri check  "Claude Code #2"
  - 无 可 用 来 源 （ 搜 索 未 返 回 结 果 ） 

✻ Baked for 46s

※ recap: 用 户 测 试 了  WebSearch 和  mcp-webresearch 
  两 个 搜 索 工 具 ， 均 未 返 回 结 果 。 下 一 步 可 尝 试 直 接 用  WebFetch 访 问  Anthropic 
  官 方 文 档 页 面 获 取 信 息 。  (disable recaps in /config)
  
❯ 你 是 什 么 模 型 ？                                                                          

⏺ 我 是  Claude Sonnet 4.6（ 1M 上 下 文 版 本 ） ， 由  Anthropic 开 发 。 

✻ Worked for 5s

─────────────────────────────────────────────────────────────────────────────────────────
❯ 
─────────────────────────────────────────────────────────────────────────────────────────
   Sonnet 4.6 1M |   waimai_cd_fe_mfe_crm_pc |   feature/claim-order-status ✓ |  5.9…
  ⏵⏵ bypass permissions on (shift+tab to cycle)

# maestri ask "Agent Name" "your prompt"
zhoulihao@macbook ~ % maestri ask "Claude Code #2" "hello"
  官 方 文 档 页 面 获 取 信 息 。  (disable recaps in /config)
  
❯ 你 是 什 么 模 型 ？                                                                          

⏺ 我 是  Claude Sonnet 4.6（ 1M 上 下 文 版 本 ） ， 由  Anthropic 开 发 。 

✻ Worked for 5s

❯ hello                                                                                  

⏺ 你 好 ！ 有 什 么 我 可 以 帮 你 的 吗 ？ 

✻ Sautéed for 6s

─────────────────────────────────────────────────────────────────────────────────────────
❯  
─────────────────────────────────────────────────────────────────────────────────────────
   Sonnet 4.6 1M |   waimai_cd_fe_mfe_crm_pc |   feature/claim-order-status ✓ |  6.6…
  ⏵⏵ bypass permissions on (shift+tab to cycle)


# maestri note read "Note Name"
zhoulihao@macbook ~ % maestri note read "note"
[14 lines total]
1       测试
2       测试测试
3       测试
4       测试
5       测试
6       测试
7       测试
8       测试
9       测试
10      测试
11      测试
12      测试
13      测试
14

# maestri note read "Note Name" 10 20`
zhoulihao@macbook ~ % maestri note read "note" 10 20
[lines 10-14 of 14]
10      测试
11      测试
12      测试
13      测试
14

# maestri note write "Note Name" "content"
zhoulihao@macbook ~ % maestri note write "note" "content"
OK
zhoulihao@macbook ~ % maestri note read "note"           
[1 lines total]
1       content

# maestri note edit "Note Name" "old text" "new text"
zhoulihao@macbook ~ % maestri note read "note"           
[1 lines total]
1       content
zhoulihao@macbook ~ % maestri note edit "note" "content" "new text"
OK
zhoulihao@macbook ~ % maestri note read "note"                     
[1 lines total]
1       new text