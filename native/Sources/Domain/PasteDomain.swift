enum PasteOutcome {
    case directInserted
    case restored
    case preservedUserClipboard
    case failed(String)
}
