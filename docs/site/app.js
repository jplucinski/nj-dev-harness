const demos = {
  flow: [
    ["prompt", "dirty"],
    ["output", "payments/.worktrees/retry-policy-20260903-101504"],
    ["prompt", "why"],
    ["accent", "feature/retry-policy · 3 changed · next TODO P1"],
    ["prompt", "focus p1"],
    ["output", "payments · Check retry metrics"],
    ["prompt", "standup --day"],
    ["accent", "Appended to today's Daily note"],
  ],
  review: [
    ["prompt", "gtask review"],
    ["output", "✓ src/RetryPolicy.java"],
    ["output", "✓ src/RetryPolicyTest.java"],
    ["accent", "Sensitive paths excluded · sending 2 files"],
    ["prompt", "gtask review -- --all"],
    ["output", "Explicit consent required for non-interactive review"],
  ],
  remember: [
    ["prompt", "gtask day -- \"Fixed payment timeout\""],
    ["accent", "Updated Daily/2026-09-03.md"],
    ["prompt", "gtask todo -- p1 \"Check retry metrics\""],
    ["accent", "Created TODO · payments · P1"],
    ["prompt", "gtask todos"],
    ["output", "P1  payments  Check retry metrics"],
  ],
};

const lines = document.querySelector("#terminal-lines");
const tabs = document.querySelectorAll("[data-demo]");
let renderToken = 0;

function renderDemo(name) {
  renderToken += 1;
  const token = renderToken;
  lines.replaceChildren();
  tabs.forEach((tab) => tab.classList.toggle("active", tab.dataset.demo === name));

  demos[name].forEach(([type, content], index) => {
    window.setTimeout(() => {
      if (token !== renderToken) return;
      const line = document.createElement("div");
      line.className = `terminal-line ${type}`;
      line.textContent = content;
      lines.append(line);
    }, index * 145);
  });
}

if (lines) {
  tabs.forEach((tab) => tab.addEventListener("click", () => renderDemo(tab.dataset.demo)));
}

document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = "copied";
      window.setTimeout(() => { button.textContent = "copy"; }, 1400);
    } catch {
      button.textContent = "select text";
    }
  });
});

const projectName = window.location.hostname.endsWith("github.io")
  ? window.location.pathname.split("/").filter(Boolean)[0]
  : "";
const ownerName = window.location.hostname.endsWith("github.io")
  ? window.location.hostname.split(".")[0]
  : "";

if (ownerName && projectName) {
  document.querySelectorAll("[data-repo-file]").forEach((link) => {
    link.href = `https://github.com/${ownerName}/${projectName}/blob/main/${link.dataset.repoFile}`;
  });
}

if (lines) {
  renderDemo("flow");
}
