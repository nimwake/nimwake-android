import { allPosts } from "../lib/posts";

export default function Home() {
  const posts = allPosts();
  return (
    <ul style={{ listStyle: "none", padding: 0 }}>
      {posts.map((p) => (
        <li key={p.slug} style={{ marginBottom: 16 }}>
          <a href={`/posts/${p.slug}`} style={{ fontSize: 18 }}>
            {p.title}
          </a>
          <div style={{ color: "#656d76", fontSize: 14 }}>{p.date}</div>
        </li>
      ))}
    </ul>
  );
}
