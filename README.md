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
  }
}
```

A token lives at most an hour, so the wiki host fetches a new one more often
than that, for example every 15 minutes from cron, and writes it to a file
that PHP can read. With the AWS CLI:

```sh
aws sts get-web-identity-token --audience chart-renderer \
  --signing-algorithm ES384 --duration-seconds 3600 \
  --query WebIdentityToken --output text > /run/secrets/chart-renderer-token
```

Or from PHP with the [AWS SDK for PHP](https://github.com/aws/aws-sdk-php),
which MediaWiki does not ship, so add `aws/aws-sdk-php` to
`composer.local.json` unless an extension such as
[AWS](https://www.mediawiki.org/wiki/Extension:AWS) already requires it:

```php
$sts = new Aws\Sts\StsClient( [
	'region' => 'us-east-1',
	'version' => '2011-06-15',
] );
$token = $sts->getWebIdentityToken( [
	'Audience' => [ 'chart-renderer' ],
	'SigningAlgorithm' => 'ES384',
	'DurationSeconds' => 3600,
] )['WebIdentityToken'];
```

`GetWebIdentityToken` is not served by the global STS endpoint, so use a
regional one (the AWS CLI does by default). Then `LocalSettings.php` reads the
file on each request:

```php
wfLoadExtension( 'Chart' );
$wgChartServiceUrl = $chartRendererUrl .
	trim( file_get_contents( '/run/secrets/chart-renderer-token' ) );
```

where `$chartRendererUrl` is the module's `url` output. Femiwiki's setup is in
[docker-mediawiki](https://github.com/femiwiki/docker-mediawiki/tree/main/dockers/femiwiki)
(`chart-renderer-token.php`, `run` and `LocalSettings.php`).

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
