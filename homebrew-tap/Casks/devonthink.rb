cask "devonthink" do
  version "3.9.16"
  sha256 "a2f29f479900cd7fc56bd574d87a64f22089ab9b5cbc8cdeb1cebf33b9220fae"

  url "https://download.devontechnologies.com/download/devonthink/#{version}/DEVONthink_3.app.zip",
      verified: "download.devontechnologies.com/"
  name "DEVONthink 3"
  desc "Collect, organise, edit and annotate documents (version-pinned to 3.9.16)"
  homepage "https://www.devontechnologies.com/apps/devonthink"

  # Disable auto-updates to preserve this version
  auto_updates false

  app "DEVONthink 3.app"

  zap trash: [
    "~/Library/Application Scripts/com.devon-technologies.*",
    "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.devon-technologies.think*.sfl*",
    "~/Library/Application Support/DEVONthink*",
    "~/Library/Caches/com.apple.helpd/Generated/com.devontechnologies.devonthink.help*",
    "~/Library/Caches/com.devon-technologies.think*",
    "~/Library/Containers/com.devon-technologies.*",
    "~/Library/Cookies/com.devon-technologies.think*.binarycookies",
    "~/Library/Group Containers/679S2QUWR8.think*",
    "~/Library/Metadata/com.devon-technologies.think*",
    "~/Library/Preferences/com.devon-technologies.think*",
    "~/Library/Saved Application State/com.devon-technologies.think*.savedState",
    "~/Library/Scripts/Applications/DEVONagent",
    "~/Library/Scripts/Folder Action Scripts/DEVONthink*",
    "~/Library/WebKit/com.devon-technologies.think*",
  ]
end
