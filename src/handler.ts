/**
 * Renders a chart for MediaWiki's Chart extension, which posts its request to
 * $wgChartServiceUrl and puts the HTML of the response, an SVG in a
 * <wiki-chart> element, into the page.
 *
 * Chart cannot add headers to that request, so the caller proves who it is in
 * the URL path instead: the path is a JWT from an OpenID Connect issuer, such
 * as AWS STS's GetWebIdentityToken. A token copied out of a log stops working
 * when it expires.
 *
 * The function URL is open to anyone, so a request is checked before its body is
 * read: the token's signature against the issuer's JWKS, its issuer, audience,
 * subject and expiry.
 */

import type {
	LambdaFunctionURLEvent,
	LambdaFunctionURLResult,
} from "aws-lambda";
import {
	type RenderParams,
	renderChart,
} from "chart-service/src/lib/render.js";
import { validateRequestParams } from "chart-service/src/lib/validation.js";
import { createRemoteJWKSet, jwtVerify } from "jose";

const list = (value: string | undefined): string[] =>
	(value ?? "")
		.split(",")
		.map((item) => item.trim())
		.filter(Boolean);

let jwks: Promise<ReturnType<typeof createRemoteJWKSet>> | undefined;

// Kept between invocations of a warm instance; jose refetches the set when a
// token names a key it has not seen.
const keySet = (issuer: string) => {
	jwks ??= (async () => {
		const response = await fetch(`${issuer}/.well-known/openid-configuration`);
		if (!response.ok) {
			throw new Error(`OpenID configuration: HTTP ${response.status}`);
		}
		const { jwks_uri } = (await response.json()) as { jwks_uri: string };
		return createRemoteJWKSet(new URL(jwks_uri));
	})().catch((error) => {
		jwks = undefined;
		throw error;
	});
	return jwks;
};

export const authorized = async (token: string): Promise<boolean> => {
	const issuer = process.env.ISSUER;
	const audiences = list(process.env.AUDIENCES);
	const subjects = list(process.env.SUBJECTS);
	const algorithms = list(process.env.ALGORITHMS);
	if (!issuer || audiences.length === 0 || subjects.length === 0 || !token) {
		return false;
	}
	try {
		const { payload } = await jwtVerify(token, await keySet(issuer), {
			issuer,
			audience: audiences,
			algorithms: algorithms.length > 0 ? algorithms : undefined,
			requiredClaims: ["exp", "sub"],
		});
		return subjects.includes(payload.sub as string);
	} catch {
		return false;
	}
};

const json = (statusCode: number, body: unknown): LambdaFunctionURLResult => ({
	statusCode,
	headers: { "content-type": "application/json" },
	body: JSON.stringify(body),
});

export const handler = async (
	event: LambdaFunctionURLEvent,
): Promise<LambdaFunctionURLResult> => {
	if (!(await authorized(event.rawPath.replace(/^\/+/, "")))) {
		return { statusCode: 401 };
	}
	if (event.requestContext.http.method !== "POST") {
		return { statusCode: 405, headers: { allow: "POST" } };
	}

	let params: unknown;
	try {
		const body = event.isBase64Encoded
			? Buffer.from(event.body ?? "", "base64").toString()
			: (event.body ?? "");
		params = JSON.parse(body);
	} catch {
		return json(400, { message: "Invalid JSON" });
	}

	const errors = validateRequestParams(params);
	if (errors.length > 0) {
		return json(400, { message: "Invalid request data", errors });
	}

	return {
		statusCode: 200,
		headers: { "content-type": "text/html" },
		body: renderChart(params as RenderParams),
	};
};
