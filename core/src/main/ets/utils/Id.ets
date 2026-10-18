/**
 * 简易 ID 生成：时间戳 + 随机数，避免引入外部 uuid 依赖。
 */
export function genId(prefix: string): string {
  const rand = Math.floor(Math.random() * 0xFFFFFF).toString(16);
  return `${prefix}_${Date.now().toString(36)}_${rand}`;
}
