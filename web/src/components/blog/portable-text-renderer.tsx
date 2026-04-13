"use client";

import {
  PortableText,
  type PortableTextComponents,
} from "@portabletext/react";
import { urlFor } from "@/sanity/client";

const components: PortableTextComponents = {
  block: {
    h2: ({ children }) => (
      <h2 className="mt-10 mb-4 font-display text-xl text-text-primary">
        {children}
      </h2>
    ),
    h3: ({ children }) => (
      <h3 className="mt-8 mb-3 font-display text-lg text-text-primary">
        {children}
      </h3>
    ),
    normal: ({ children }) => (
      <p className="mb-5 font-body text-[15px] text-text-secondary leading-[1.8]">
        {children}
      </p>
    ),
    blockquote: ({ children }) => (
      <blockquote className="my-6 border-l-2 border-coral/30 pl-5 font-body italic text-text-tertiary">
        {children}
      </blockquote>
    ),
  },
  list: {
    bullet: ({ children }) => (
      <ul className="mb-5 list-disc pl-6 space-y-1.5 font-body text-[15px] text-text-secondary">
        {children}
      </ul>
    ),
    number: ({ children }) => (
      <ol className="mb-5 list-decimal pl-6 space-y-1.5 font-body text-[15px] text-text-secondary">
        {children}
      </ol>
    ),
  },
  marks: {
    strong: ({ children }) => (
      <strong className="font-semibold text-text-primary">{children}</strong>
    ),
    em: ({ children }) => <em>{children}</em>,
    code: ({ children }) => (
      <code className="rounded bg-bg-elevated px-1.5 py-0.5 font-mono text-xs">
        {children}
      </code>
    ),
    link: ({ children, value }) => (
      <a
        href={value?.href}
        className="text-coral hover:underline"
        target={value?.href?.startsWith("http") ? "_blank" : undefined}
        rel={
          value?.href?.startsWith("http")
            ? "noopener noreferrer"
            : undefined
        }
      >
        {children}
      </a>
    ),
  },
  types: {
    image: ({ value }) => {
      if (!value?.asset?._ref) return null;
      return (
        <figure className="my-8">
          <img
            src={urlFor(value).width(800).url()}
            alt={value.alt || ""}
            className="w-full rounded-lg"
          />
          {value.caption && (
            <figcaption className="mt-2 text-center font-mono text-xs text-text-tertiary">
              {value.caption}
            </figcaption>
          )}
        </figure>
      );
    },
  },
};

import type { PortableTextBlock } from "@portabletext/types";

interface PortableTextRendererProps {
  value: PortableTextBlock[];
}

export function PortableTextRenderer({ value }: PortableTextRendererProps) {
  return <PortableText value={value} components={components} />;
}
