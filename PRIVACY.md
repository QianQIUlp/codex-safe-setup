# Privacy

Codex Safe Setup's bundled PowerShell scripts do not contain telemetry, analytics, advertising, or an independent data-upload service. Assessment is designed to inspect configuration, tool versions, and the existence of known sensitive paths without reading secret contents.

The plugin operates inside ChatGPT or Codex. Prompts, model context, terminal output, and any separately invoked product tools are handled by the host product and the services you choose to use, under their own terms and privacy controls. This project does not control Web Search, Browser, Computer Use, apps, connectors, other plugins, MCP servers, cloud tasks, Git remotes, or CI services.

Command networking is off by default. An allowlist applies only when the Codex command proxy is enabled. Unrestricted command networking requires an explicit high-risk acknowledgement.

Do not provide real secrets as test data. If a credential may have been exposed, revoke or rotate it and review provider activity.
