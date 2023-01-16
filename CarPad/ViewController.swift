// Developed by Ben Dodson (ben@bendodson.com)

import UIKit
import UniformTypeIdentifiers
import AVKit

public enum BSSError: Error {
    case staleBookmark
    case noFiles
}

extension BSSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .staleBookmark:
            return NSLocalizedString("The bookmark to your selected folder has expired. Please try again.", comment: "")
        case .noFiles:
            return NSLocalizedString("No video files were found in your selected folder.", comment: "")
        }
    }
}


class ViewController: UIViewController {

    private var bookmark: Data?
    private var player: AVQueuePlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Back Seat Shuffle"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus.rectangle"), style: .plain, target: self, action: #selector(presentDocumentPicker))
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // if there is no bookmark, then present the document picker (will also trigger when video queue ends)
        if bookmark == nil {
            presentDocumentPicker()
        }
    }

    @objc func presentDocumentPicker() {
        // present a document picker in folder selection mode
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

    @objc func playerItemDidFinish() {
        // destroy our bookmark and dismiss the player if we've finished the last item in the queue
        guard player?.items().last == player?.currentItem else { return }
        bookmark = nil
        dismiss(animated: true)
    }
}

extension ViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        // make sure we stop accessing the resource once we exit scope (which will be as soon as the video starts playing)
        defer { url.stopAccessingSecurityScopedResource() }

        // we don't care about the return value for this as we'll try to create a bookmark anyway
        _ = url.startAccessingSecurityScopedResource()

        // store the bookmark data locally or silently fail
        bookmark = try? url.bookmarkData()

        // try to play the video; if there is an error, display an alert
        do {
            try playVideos()
        } catch {
            let controller = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: "OK", style: .default))
            present(controller, animated: true)
        }
    }

    private func playVideos() throws {
        guard let bookmark else { return }

        // get the local url from our bookmark; if the bookmark is stale (i.e. access has expired), then return
        var stale = false
        let directoryUrl = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        let path = directoryUrl.path
        guard !stale else {
            throw BSSError.staleBookmark
        }

        // get the contents of the folder; only return mp4 and mkv files; if no files, throw an error
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        let urls = contents.filter({ $0.hasSuffix("mp4") || $0.hasSuffix("mkv") }).map({ URL(filePath: path + "/" + $0) })
        guard urls.count > 0 else {
            throw BSSError.noFiles
        }

        // present the video player with the videos in a random order
        presentPlayer(urls.shuffled())
    }

    private func presentPlayer(_ urls: [URL]) {
        // set the audio session so video audio is heard even if device is muted
        try? AVAudioSession.sharedInstance().setCategory(.playback)

        // create a queue of player items from the provided urls
        let items = urls.map { AVPlayerItem(url: $0) }
        player = AVQueuePlayer(items: items)

        // present the player
        let playerController = AVPlayerViewController()
        playerController.player = player
        present(playerController, animated: true) {
            self.player?.play()
        }
    }

}
