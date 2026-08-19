// Pure decision logic for tool-call guards. The index.js adapter normalizes
// real dsh tool arguments ({ url } for web_fetch, { file_path } / { path } for
// filesystem tools — field names verified in tool-web/fetch.ts and tool-fs)
// and applies these verdicts.
// Coverage honesty (wizard must state this):
//   - web_fetch guard: enforced at the tool pipeline (PASS-able)
//   - network started by bash subprocesses: NOT CONTROLLED (dsh has no network sandbox)
//   - fs read guard: enforced for filesystem tools only (PARTIAL — bash `cat` bypasses)

function hostOf(url) {
  try {
    return new URL(url).hostname.toLowerCase()
  } catch {
    return null
  }
}

// networkMode: { key: 'off'|'allowlist'|'unrestricted', allowlist: string[]|null }
export function checkWebFetch(url, networkMode) {
  if (!networkMode || networkMode.key === 'unrestricted') {
    return { allowed: true, reason: null }
  }
  const host = hostOf(url)
  if (!host) {
    return { allowed: false, reason: 'web_fetch 目标不是可解析的 URL。' }
  }
  if (networkMode.key === 'off') {
    return { allowed: false, reason: `联网已关闭（web_fetch 拒绝 ${host}）。` }
  }
  const allowlist = networkMode.allowlist || []
  const hit = allowlist.find((entry) => {
    const allowed = entry.toLowerCase().trim()
    return host === allowed || host.endsWith('.' + allowed)
  })
  if (!hit) {
    return {
      allowed: false,
      reason: `目标 ${host} 不在联网白名单内（允许：${allowlist.join(', ') || '<空>'}）。`,
    }
  }
  return { allowed: true, reason: null }
}

// Minimal glob → RegExp for '**/name' style patterns: '**/' matches any
// leading directories, '*' matches within one segment, everything else is
// literal. Single-pass scan so inserted regex parts are never re-processed.
export function globToRegex(pattern) {
  const source = pattern.replace(/\\/g, '/').toLowerCase().replace(/[.+?^${}()|[\]]/g, '\\$&')
  let out = ''
  for (let i = 0; i < source.length;) {
    if (source.startsWith('**/', i)) { out += '(?:.*/)?'; i += 3 }
    else if (source.startsWith('**', i)) { out += '.*'; i += 2 }
    else if (source[i] === '*') { out += '[^/]*'; i += 1 }
    else { out += source[i]; i += 1 }
  }
  return new RegExp(`^${out}$`)
}

export function checkFsRead(path, denyGlobs) {
  if (!path) return { allowed: true, reason: null }
  const normalized = String(path).replace(/\\/g, '/').toLowerCase()
  for (const pattern of denyGlobs || []) {
    if (globToRegex(pattern).test(normalized)) {
      return {
        allowed: false,
        reason: `受保护路径（匹配 ${pattern}）：${pattern.includes('.credentials.yaml') ? '凭据文件' : '敏感文件'}读取被拒绝。此拦截不覆盖 bash 命令发起的读取。`,
      }
    }
  }
  return { allowed: true, reason: null }
}
