// content/*.md를 읽는다. 의존성을 늘리지 않으려고 front matter와 마크다운을 직접 다룬다 —
// 이 앱은 폰에서 깨어나는 비용을 재는 예시이고, 필요한 문법만 지원한다.
import fs from "node:fs";
import path from "node:path";

const dir = path.join(process.cwd(), "content");

// ---\ntitle: …\ndate: …\n---\n본문
function parse(raw) {
  const meta = {};
  let body = raw;
  const m = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  if (m) {
    for (const line of m[1].split("\n")) {
      const i = line.indexOf(":");
      if (i > 0) meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
    body = raw.slice(m[0].length);
  }
  return { meta, body };
}

export function allPosts() {
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => {
      const { meta } = parse(fs.readFileSync(path.join(dir, f), "utf8"));
      return { slug: f.replace(/\.md$/, ""), title: meta.title ?? f, date: meta.date ?? "" };
    })
    .sort((a, b) => (a.date < b.date ? 1 : -1));
}

export function post(slug) {
  const file = path.join(dir, `${slug}.md`);
  if (!fs.existsSync(file)) return null;
  const { meta, body } = parse(fs.readFileSync(file, "utf8"));
  return { slug, title: meta.title ?? slug, date: meta.date ?? "", blocks: blocks(body) };
}

// 지원: # 제목, ## 소제목, - 목록, ``` 코드 블록, 빈 줄로 나뉜 문단
function blocks(body) {
  const out = [];
  const lines = body.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith("```")) {
      const code = [];
      for (i++; i < lines.length && !lines[i].startsWith("```"); i++) code.push(lines[i]);
      out.push({ kind: "code", text: code.join("\n") });
    } else if (line.startsWith("## ")) {
      out.push({ kind: "h3", text: line.slice(3) });
    } else if (line.startsWith("# ")) {
      out.push({ kind: "h2", text: line.slice(2) });
    } else if (line.startsWith("- ")) {
      const items = [line.slice(2)];
      while (i + 1 < lines.length && lines[i + 1].startsWith("- ")) items.push(lines[++i].slice(2));
      out.push({ kind: "list", items });
    } else if (line.trim() !== "") {
      const para = [line];
      while (i + 1 < lines.length && lines[i + 1].trim() !== "" && !/^(#|- |```)/.test(lines[i + 1])) para.push(lines[++i]);
      out.push({ kind: "p", text: para.join(" ") });
    }
  }
  return out;
}
