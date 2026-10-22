import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import {
	Link,
	Outlet,
	RouterProvider,
	createRootRoute,
	createRoute,
	createRouter,
} from "@tanstack/react-router";

// 경로는 브라우저에서 그린다 — 폰의 정적 서버는 /about 같은 경로에 index.html을 준다 (SPA = "1")
const rootRoute = createRootRoute({
	component: () => (
		<main style={{ fontFamily: "system-ui, sans-serif", maxWidth: 640, margin: "2rem auto", padding: "0 1rem" }}>
			<nav style={{ display: "flex", gap: "1rem" }}>
				<Link to="/">home</Link>
				<Link to="/about">about</Link>
			</nav>
			<Outlet />
		</main>
	),
	notFoundComponent: () => <p>없는 페이지다.</p>,
});

const homeRoute = createRoute({
	getParentRoute: () => rootRoute,
	path: "/",
	component: () => (
		<>
			<h1>폰에서 도는 정적 사이트</h1>
			<p>Vite로 빌드해 Nimwake가 깨우는 정적 서버가 내준다. 요청이 없으면 잠든다.</p>
		</>
	),
});

const aboutRoute = createRoute({
	getParentRoute: () => rootRoute,
	path: "/about",
	component: () => (
		<>
			<h1>about</h1>
			<p>이 주소로 바로 들어와도(새로고침) 열린다 — 서버가 index.html을 주고 라우터가 이 페이지를 그린다.</p>
		</>
	),
});

const router = createRouter({ routeTree: rootRoute.addChildren([homeRoute, aboutRoute]) });

createRoot(document.getElementById("root")).render(
	<StrictMode>
		<RouterProvider router={router} />
	</StrictMode>,
);
