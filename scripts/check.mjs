/* 语法检查：把单文件 HTML 里的 <script>...</script> 抽出来，
   用 Node 的 `node --check` 做一次静态语法校验。
   通过 -> 退出码 0；有语法错误 -> 非 0，供 CI 门禁。
   临时文件放 os.tmpdir()，退出码用 process.exitCode 传递，
   让 finally 的清理始终执行（不在 try 内直接 process.exit）。 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import { spawnSync } from 'child_process';

const html = fs.readFileSync('zl-worklog.html', 'utf8');
const m = html.match(/<script>([\s\S]*)<\/script>/);
if (!m) {
  console.error('❌ 未找到 <script> 块');
  process.exitCode = 1;
} else {
  const js = m[1];
  const tmp = path.join(os.tmpdir(), 'syntax_check_' + process.pid + '_' + Date.now() + '.mjs');
  fs.writeFileSync(tmp, js);
  try {
    const r = spawnSync('node', ['--check', tmp], { stdio: 'inherit' });
    if (r.status !== 0) {
      console.error('❌ node --check 失败');
      process.exitCode = r.status || 1;
    } else {
      console.log('✅ 语法检查通过');
    }
  } finally {
    try { fs.unlinkSync(tmp); } catch (e) { /* 忽略清理失败 */ }
  }
}
