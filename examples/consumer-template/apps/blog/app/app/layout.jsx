export const metadata = { title: "My blog", description: "Served from an Android phone by Nimwake" };

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body style={{ fontFamily: "system-ui, sans-serif", maxWidth: 680, margin: "0 auto", padding: "24px 16px" }}>
        {children}
      </body>
    </html>
  );
}
