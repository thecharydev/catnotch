# Template for Casks/desknotch.rb in the Homebrew tap repo. The release
# workflow (.github/workflows/release-mac.yml) fills in VERSION and SHA256.
cask "desknotch" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/OWNER/catnotch/releases/download/#{version}/CatNotch-#{version}-universal.dmg"
  name "CatNotch"
  desc "Notch-style bar for the top of your screen"
  homepage "https://github.com/OWNER/catnotch"

  depends_on macos: ">= :ventura"

  app "CatNotch.app"

  # The build is ad hoc signed, not notarized: without this macOS blocks the
  # first open. Installing through the cask is the recommended path.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/CatNotch.app"]
  end

  zap trash: [
    "~/Library/Application Support/CatNotch",
    "~/Library/Preferences/com.devezio.desknotch.plist",
  ]
end
