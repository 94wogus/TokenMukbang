# Homebrew Cask for TokenMukbang.
#
# Copy this into a personal tap (`94wogus/homebrew-tap`) under Casks/, fill in the
# real `sha256` from the notarized DMG, and users install with:
#
#   brew install --cask 94wogus/tap/token-mukbang
#
# The signed + notarized DMG release pipeline is ADR-0010 (needs an Apple Developer
# account); this file is the distribution artifact, not the signing itself.
cask "token-mukbang" do
  version "0.1.0"
  sha256 :no_check   # replace with the notarized DMG's shasum -a 256 on release

  url "https://github.com/94wogus/TokenMukbang/releases/download/v#{version}/TokenMukbang-#{version}.dmg"
  name "Token Mukbang"
  desc "Menu-bar widget that watches Claude eat your tokens (live)"
  homepage "https://github.com/94wogus/TokenMukbang"

  depends_on macos: ">= :sonoma"   # macOS 14+

  app "TokenMukbang.app"

  zap trash: [
    "~/Library/Application Support/ClaudeUsageWidget",
    "~/Library/Containers/com.94wogus.tokenmukbang.widget",
  ]
end
