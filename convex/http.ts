import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";

const http = httpRouter();

http.route({
  path: "/health",
  method: "GET",
  handler: httpAction(async () =>
    new Response(JSON.stringify({ service: "sensor-bio-product-loop", schemaVersion: 1 }), {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    }),
  ),
});

export default http;
