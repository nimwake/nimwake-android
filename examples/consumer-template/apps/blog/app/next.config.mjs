// 폰에 놓을 묶음은 standalone이어야 한다 — server.js + 필요한 node_modules만 (폰에서 npm install하지 않는다)
// images.unoptimized: 이미지 최적화(sharp)는 네이티브 모듈이라 빌드 머신의 CPU용이 묶음에 들어가 폰에서 깨진다
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  poweredByHeader: false,
  images: { unoptimized: true },
};

export default nextConfig;
