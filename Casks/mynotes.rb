cask "mynotes" do
  version "1.0"
  sha256 :no_check

  url "https://github.com/gnyanarushi/myNotes/releases/download/v#{version}/MyNotes-macOS-#{version}.zip",
      verified: "github.com/gnyanarushi/myNotes/"
  name "MyNotes"
  desc "Local-first notebook for writing, sketching, and PDF export"
  homepage "https://github.com/gnyanarushi/myNotes"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "MyNotes.app"

  zap trash: [
    "~/Library/Preferences/tech.gnyanarushi.MyNotesMac.plist",
    "~/Library/Saved Application State/tech.gnyanarushi.MyNotesMac.savedState",
  ]
end
