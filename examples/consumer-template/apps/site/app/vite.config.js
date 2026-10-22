import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 빌드 결과는 dist/ — build-app.sh가 그대로 site/로 묶는다. 폰에서는 빌드하지 않는다
export default defineConfig({
	plugins: [react()],
});
