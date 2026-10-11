import SwiftUI

extension EnvironmentValues {
    /// True while the offscreen snapshot tool renders a view. Views use it only to approximate effects that
    /// can't be captured offscreen (Liquid Glass, materials); never to change content (spec §13.3).
    @Entry public var isSnapshot: Bool = false
}
