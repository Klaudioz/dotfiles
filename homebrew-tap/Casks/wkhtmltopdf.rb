cask "wkhtmltopdf" do
  version "0.12.6-2"
  sha256 "81a66b77b508fede8dbcaa67127203748376568b3673a17f6611b6d51e9894f8"

  url "https://github.com/wkhtmltopdf/packaging/releases/download/#{version}/wkhtmltox-#{version}.macos-cocoa.pkg"
  name "wkhtmltopdf"
  desc "Convert HTML to PDF using WebKit rendering engine"
  homepage "https://wkhtmltopdf.org/"

  pkg "wkhtmltox-#{version}.macos-cocoa.pkg"

  uninstall pkgutil: "org.wkhtmltopdf.wkhtmltox"
end
