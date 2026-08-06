import ManagedSettings
import ManagedSettingsUI
import SwiftUI
import UIKit

/// The screen you actually hit when you open Instagram mid-session.
///
/// iOS renders this, not the app, so it works with Locked force-quit. It reads
/// the session snapshot out of the app group so the copy is specific: your own
/// goal, the time left, and the names of the people who will hear about it.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        locked()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        locked()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        locked()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        locked()
    }

    // MARK: Copy

    private func locked() -> ShieldConfiguration {
        let snapshot = SessionSnapshot.load()

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(Color(hex: Hex.groundDeep, alpha: 0.94)),
            icon: UIImage(systemName: "lock"),
            title: ShieldConfiguration.Label(
                text: title(snapshot),
                color: UIColor(Ink.paper)
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle(snapshot),
                color: UIColor(Ink.paper(0.6))
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Back to work",
                color: UIColor(Color(hex: Hex.groundDeep))
            ),
            primaryButtonBackgroundColor: UIColor(Ink.gold)
        )
    }

    private func title(_ snapshot: SessionSnapshot?) -> String {
        guard let snapshot, snapshot.isRunning else { return "Locked" }
        return "\(Fmt.span(snapshot.remaining)) left"
    }

    private func subtitle(_ snapshot: SessionSnapshot?) -> String {
        guard let snapshot, snapshot.isRunning else {
            return "Locked is holding this app. Open Locked to see why."
        }
        return "\(snapshot.goal)\n\(snapshot.watcherLine)"
    }
}
