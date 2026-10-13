// 이 앱을 깨운 요청과 지금의 프로세스를 그대로 돌려준다. 측정 · 확인용이다.
//   x-forwarded-for  Core PRD §81 — 맨 오른쪽이 gateway가 관측한 peer (#41 I2)
//   pid · uptime      Nimwake가 같은 프로세스로 응답했는가(warm), 새로 띄웠는가(cold)
//   rss_mb            깨어 있는 동안의 메모리 (#42 임계값의 근거)
export const dynamic = "force-dynamic";

export function GET(request) {
  const h = request.headers;
  const mem = process.memoryUsage();
  return Response.json({
    app: "blog",
    pid: process.pid,
    uptime_s: Math.round(process.uptime() * 10) / 10,
    rss_mb: Math.round((mem.rss / 1048576) * 10) / 10,
    heap_used_mb: Math.round((mem.heapUsed / 1048576) * 10) / 10,
    node: process.version,
    host: h.get("host"),
    x_forwarded_for: h.get("x-forwarded-for"),
    x_forwarded_proto: h.get("x-forwarded-proto"),
    user_agent: h.get("user-agent"),
  });
}
