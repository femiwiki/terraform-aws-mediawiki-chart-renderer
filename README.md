# terraform-aws-mediawiki-chart-renderer

An OpenTofu and Terraform module for an AWS Lambda function that renders charts
for MediaWiki's [Chart extension](https://www.mediawiki.org/wiki/Extension:Chart).

The Chart extension can render charts by running Node.js on the wiki's own host,
or by sending each chart to a chart service at `$wgChartServiceUrl`. This module
runs that service on Lambda, so the wiki host needs neither Node.js nor the
memory a render takes.

## License

[MIT](LICENSE)
