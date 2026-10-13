// standalone: 실행에 필요한 파일만 .next/standalone/에 모은다 (server.js + 필요한 node_modules).
// 개발 머신에서 빌드하고 폰은 그 결과만 `node server.js`로 돌린다 — 폰에서 npm install · next build를 하지 않는다.
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  poweredByHeader: false,
  // 이미지 최적화는 sharp(네이티브 모듈)를 쓴다. 빌드 머신의 x86_64 binary가 묶음에 들어가 폰(aarch64)에서 깨진다.
  // 이 블로그는 쓰지 않는다 — scripts/build-app.sh가 sharp를 묶음에서 빼고 남은 네이티브 모듈이 있으면 멈춘다
  images: { unoptimized: true },
};

export default nextConfig;
