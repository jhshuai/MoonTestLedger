///|
async fn version() -> Int32 {
  @stdio.stdout.write(
    Json::object({
      "schema": Json::number(1),
      "name": Json::string("MoonTestLedger"),
      "module": Json::string("jhshuai/moontestledger"),
      "version": Json::string("0.1.0"),
      "license": Json::string("Apache-2.0"),
      "cli_targets": Json::array([Json::string("wasm"), Json::string("native")]),
      "delivery_profiles": Json::array([Json::string("mtl-ci-delivery-v1")]),
    }).stringify(indent=2) +
    "\n",
  )
  0
}
