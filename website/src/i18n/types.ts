export interface Link {
  label: string;
  href: string;
  external?: boolean;
}

export interface LimitItem {
  icon: 'allow' | 'deny';
  label: string;
  detail?: string;
}

export interface BoundaryModule {
  id: string;
  number: string;
  eyebrow: string;
  title: string;
  lead: string;
  inside: LimitItem[];
  outside: LimitItem[];
  note: string;
}

export interface VerificationRow {
  status: 'pass' | 'partial' | 'fail' | 'not-controlled';
  label: string;
  detail: string;
}

export interface PrincipleExample {
  label: string;
  code: string[];
  looksLike: string;
  actually: string;
  decodedLabel?: string;
  decoded?: string[];
}

export interface UiContent {
  lang: string;
  altLang: 'en' | 'zh-CN';
  altLangLabel: string;
  altLangHref: string;
  path: string;
  meta: {
    title: string;
    description: string;
    ogTitle: string;
    ogDescription: string;
  };
  nav: {
    howItWorks: Link;
    install: Link;
    threatModel: Link;
    github: Link;
  };
  hero: {
    eyebrow: string;
    title: string;
    lead: string;
    primaryCta: Link;
    secondaryCta: Link;
    tertiaryCta: Link;
    disclaimer: string;
    visual: {
      agentLabel: string;
      agentName: string;
      insideLabel: string;
      outsideLabel: string;
      allowed: string[];
      denied: string[];
      deniedCrossing: string;
      crossingDetail: string;
      ariaLabel: string;
    };
  };
  principle: {
    eyebrow: string;
    title: string;
    body: string[];
    semantic: {
      label: string;
      intro: string;
      code: string[];
      looksLike: string;
      actually: string;
      answer: {
        caption: string;
        keyLines: string[];
        explanation: string;
      };
    };
    accidents: {
      label: string;
      intro: string;
      examples: PrincipleExample[];
    };
    boundary: {
      label: string;
      intro: string;
      examples: PrincipleExample[];
      incident: {
        label: string;
        story: string;
        lesson: string;
      };
    };
    closer: string;
    cta: string;
  };
  limits: {
    eyebrow: string;
    title: string;
    lead: string;
    modules: BoundaryModule[];
  };
  beforeAfter: {
    eyebrow: string;
    title: string;
    lead: string;
    before: { title: string; tagline: string; items: string[] };
    after: { title: string; tagline: string; items: string[] };
    afterDenied: string;
    bottomLine: string;
    modes: {
      label: string;
      intro: string;
      recommendedTag: string;
      rows: { name: string; recommended?: boolean; detail: string }[];
    };
  };
  verification: {
    eyebrow: string;
    title: string;
    lead: string;
    rows: VerificationRow[];
    caveat: string;
    restart: string;
    checks: { label: string; items: string[] };
    canary: string;
  };
  install: {
    eyebrow: string;
    title: string;
    lead: string;
    requires: string;
    commands: string[];
    promptLabel: string;
    promptText: string;
    releaseNote: string;
    shaNote: string;
    detailsCta: Link;
    copyButton: string;
    copied: string;
    flow: { label: string; steps: string[] };
  };
  notProtected: {
    eyebrow: string;
    title: string;
    lead: string;
    items: string[];
    reportedAs: string;
    cta: Link;
    exposed: { label: string; items: string[] };
  };
  openSource: {
    eyebrow: string;
    title: string;
    lead: string;
    items: { label: string; href: string }[];
    cta: Link;
    facts: string[];
  };
  footer: {
    tagline: string;
    disclaimer: string;
    links: { label: string; href: string }[];
    languageLabel: string;
  };
}
