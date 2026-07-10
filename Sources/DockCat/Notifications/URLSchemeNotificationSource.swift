import DockCatCore
import Foundation

struct URLSchemeNotificationSource {
    let parser: URLSchemeParser
    func notification(from url: URL) throws -> DockCatNotification { try parser.parse(url) }
}
