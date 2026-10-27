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

The wiki's role then needs `sts:GetWebIdentityToken` for the audience
`chart-renderer`, and the wiki gets a fresh token before the last one expires
and sets:

```php
$wgChartServiceUrl = "$chartRendererUrl$token";
```

where `$chartRendererUrl` is the module's `url` output.

## Development

```sh
npm ci
npm test
```

`dist/index.js` is the bundled function. The release pull request rebuilds it,
so a pull request does not need to.

## License

[MIT](LICENSE)
