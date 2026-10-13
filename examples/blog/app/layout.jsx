export const metadata = {
  title: "폰 서버 블로그",
  description: "Nimwake가 Android 폰에서 깨워 서빙하는 블로그",
};

const style = {
  fontFamily: "system-ui, -apple-system, 'Apple SD Gothic Neo', sans-serif",
  maxWidth: 680,
  margin: "0 auto",
  padding: "24px 16px",
  lineHeight: 1.7,
  color: "#1f2328",
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body style={style}>
        <header style={{ marginBottom: 32 }}>
          <a href="/" style={{ color: "inherit", textDecoration: "none", fontWeight: 700 }}>
            폰 서버 블로그
          </a>
          <span style={{ color: "#656d76", marginLeft: 8, fontSize: 14 }}>Galaxy A51 · Termux · Nimwake</span>
        </header>
        <main>{children}</main>
      </body>
    </html>
  );
}
