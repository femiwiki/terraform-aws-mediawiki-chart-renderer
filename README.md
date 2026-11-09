# terraform-aws-mediawiki-chart-renderer

An OpenTofu and Terraform module for an AWS Lambda function that renders charts
for MediaWiki's [Chart extension](https://www.mediawiki.org/wiki/Extension:Chart).

The Chart extension can render charts by running Node.js on the wiki's own host,
or by sending each chart to a chart service at `$wgChartServiceUrl`. This module
runs that service on Lambda, so the wiki host needs neither Node.js nor the
memory a render takes.

## Usage

The function URL is open to anyone, so every request carries a JWT in its
path, and the function renders only for a token signed by `issuer` for one of
`audiences` and one of `subjects` that has not expired. Chart cannot send
headers, which is why the token goes in the path.

Any OpenID Connect issuer works. On AWS, STS signs such tokens for an IAM
role with
[GetWebIdentityToken](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetWebIdentityToken.html),
so the wiki needs no stored secret:

```hcl
resource "aws_iam_outbound_web_identity_federation" "this" {}

module "chart_renderer" {
  source  = "femiwiki/mediawiki-chart-renderer/aws"
  version = "~> 0.1"

  issuer     = aws_iam_outbound_web_identity_federation.this.issuer_identifier
  subjects   = [aws_iam_role.wiki.arn]
  algorithms = ["ES384"]
}
```

### The wiki's side

The wiki's IAM role may ask STS for such tokens:

```hcl
data "aws_iam_policy_document" "chart_token" {
  statement {
    actions   = ["sts:GetWebIdentityToken"]
    resources = ["*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "sts:IdentityTokenAudience"
      values   = ["chart-renderer"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:SigningAlgorithm"
      values   = ["ES384"]
    }

    condition {
      test     = "NumericLessThanEquals"
      variable = "sts:DurationSeconds"
      values   = ["3600"]
    }
  }
}
```

A token lives at most an hour, so the wiki host fetches a new one more often
than that, for example every 15 minutes from cron. It writes the token to a
file that only PHP can read, and replaces the file whole so that PHP never reads
half a token. With AWS CLI v2:

```sh
umask 077
aws sts get-web-identity-token --audience chart-renderer \
  --signing-algorithm ES384 --duration-seconds 3600 \
  --query WebIdentityToken --output text > /run/secrets/.chart-renderer-token &&
  chown www-data /run/secrets/.chart-renderer-token &&
  mv /run/secrets/.chart-renderer-token /run/secrets/chart-renderer-token
```

Or from PHP with the [AWS SDK for PHP](https://github.com/aws/aws-sdk-php),
which MediaWiki does not ship, so add `aws/aws-sdk-php` to
`composer.local.json` unless an extension such as
[AWS](https://www.mediawiki.org/wiki/Extension:AWS) already requires it:

```php
$sts = new Aws\Sts\StsClient( [
	'region' => 'ap-northeast-2',
	'version' => '2011-06-15',
	'sts_regional_endpoints' => 'regional',
] );
$token = $sts->getWebIdentityToken( [
	'Audience' => [ 'chart-renderer' ],
	'SigningAlgorithm' => 'ES384',
	'DurationSeconds' => 3600,
] )['WebIdentityToken'];
```

`GetWebIdentityToken` is not served by the global STS endpoint, so the client
must use a regional one. AWS CLI v2 does by default; AWS CLI v1 and the SDK for
PHP may not, hence `sts_regional_endpoints` above.

Then `LocalSettings.php` reads the file on each request:

```php
wfLoadExtension( 'Chart' );
$chartRendererToken = '/run/secrets/chart-renderer-token';
if ( is_readable( $chartRendererToken ) ) {
	$wgChartServiceUrl = $chartRendererUrl .
		trim( file_get_contents( $chartRendererToken ) );
}
```

where `$chartRendererUrl` is the address of a retrying proxy in front of the
module's `url` output, as described below. Femiwiki's setup is in
[docker-mediawiki](https://github.com/femiwiki/docker-mediawiki/tree/main/dockers/femiwiki)
(`chart-renderer-token.php`, `run` and `LocalSettings.php`) and
[infra](https://github.com/femiwiki/infra/blob/main/serving/Caddyfile).

### A retrying proxy

`reserved_concurrent_executions` caps how many renders run at once, and Lambda
answers a request over the cap with 429. Chart sends each chart once and never
retries, and the page that asked is cached with the chart's error in it. So the
wiki should not call the function URL directly: it should go through a proxy on
its own host that retries a 429.

With [Caddy](https://caddyserver.com/) 2.11.3 or later, which can retry on a
response status:

```caddyfile
http://127.0.0.1:8090 {
	bind 127.0.0.1

	reverse_proxy https://{$CHART_RENDERER_HOST} {
		# Keeps the chart so a retry can send it again
		request_buffers 4MB
		header_up Host {upstream_hostport}
		lb_try_duration 5s
		lb_try_interval 500ms
		lb_retry_match {
			expression `{rp.status_code} == 429`
		}
	}
}
```

With [nginx](https://nginx.org/), which passes a request on to the next server
of an upstream and so needs the function's host listed more than once:

```nginx
upstream chart_renderer {
	server ${CHART_RENDERER_HOST}:443 max_fails=0;
	server ${CHART_RENDERER_HOST}:443 max_fails=0;
	server ${CHART_RENDERER_HOST}:443 max_fails=0;
}

server {
	listen 127.0.0.1:8090;

	location / {
		proxy_pass https://chart_renderer;
		proxy_set_header Host ${CHART_RENDERER_HOST};
		proxy_ssl_server_name on;
		proxy_ssl_name ${CHART_RENDERER_HOST};
		proxy_http_version 1.1;
		proxy_next_upstream error timeout http_429 non_idempotent;
		proxy_next_upstream_tries 10;
		proxy_next_upstream_timeout 5s;
	}
}
```

nginx tries again at once rather than after a wait, and each address the name
resolves to counts as a server, so the number of tries is what bounds it.
nginx also resolves the name only when it starts, unless the servers have the
`resolve` parameter (nginx 1.27.3 or later, with a `resolver` and a `zone`).

`CHART_RENDERER_HOST` is the host of the module's `url` output, such as
`abcdefgh.lambda-url.ap-northeast-2.on.aws`. Then `$chartRendererUrl` is
`http://127.0.0.1:8090/`. The proxy must listen only where the wiki can reach
it, since anything that can reach it can spend the function's concurrency.

## Development

```sh
npm ci
npm test
```

`dist/index.js` is the bundled function and `dist/renderer.zip` the archive
Lambda runs. The release pull request rebuilds both, so a pull request does not
need to.

## License

[MIT](LICENSE)
