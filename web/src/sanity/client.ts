import { createClient } from "@sanity/client";
import imageUrlBuilder from "@sanity/image-url";
import { sanityConfig } from "./config";

export const sanityClient = createClient({
  ...sanityConfig,
  token: process.env.SANITY_API_TOKEN,
});

const builder = imageUrlBuilder(sanityClient);

export function urlFor(source: { _type: string; asset: { _ref: string } }) {
  return builder.image(source);
}
