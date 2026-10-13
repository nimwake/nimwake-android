import { notFound } from "next/navigation";
import { allPosts, post } from "../../../lib/posts";

// 빌드 때 글마다 HTML을 만든다 — 폰에서 렌더링 비용 없이 파일을 내준다
export function generateStaticParams() {
  return allPosts().map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({ params }) {
  const { slug } = await params;
  const p = post(slug);
  return { title: p ? p.title : "없는 글" };
}

const code = { background: "#f6f8fa", padding: 12, borderRadius: 6, overflowX: "auto", fontSize: 14 };

export default async function Post({ params }) {
  const { slug } = await params;
  const p = post(slug);
  if (!p) notFound();
  return (
    <article>
      <h1 style={{ marginBottom: 4 }}>{p.title}</h1>
      <div style={{ color: "#656d76", fontSize: 14, marginBottom: 24 }}>{p.date}</div>
      {p.blocks.map((b, i) => {
        if (b.kind === "h2") return <h2 key={i}>{b.text}</h2>;
        if (b.kind === "h3") return <h3 key={i}>{b.text}</h3>;
        if (b.kind === "code") return <pre key={i} style={code}>{b.text}</pre>;
        if (b.kind === "list")
          return (
            <ul key={i}>
              {b.items.map((t, j) => (
                <li key={j}>{t}</li>
              ))}
            </ul>
          );
        return <p key={i}>{b.text}</p>;
      })}
    </article>
  );
}
