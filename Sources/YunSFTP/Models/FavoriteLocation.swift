import Foundation
import SwiftUI

public struct FavoriteLocation: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let systemIconName: String
    public let isCustom: Bool

    public init(name: String, url: URL, systemIconName: String, isCustom: Bool = false) {
        self.id = url.path
        self.name = name
        self.url = url
        self.systemIconName = systemIconName
        self.isCustom = isCustom
    }

    public static var defaultFavorites: [FavoriteLocation] {
        let fm = FileManager.default
        var list: [FavoriteLocation] = []

        let home = fm.homeDirectoryForCurrentUser
        list.append(FavoriteLocation(name: "Home", url: home, systemIconName: "house"))

        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            list.append(FavoriteLocation(name: "Desktop", url: desktop, systemIconName: "display"))
        }

        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            list.append(FavoriteLocation(name: "Documents", url: docs, systemIconName: "folder"))
        }

        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            list.append(FavoriteLocation(name: "Downloads", url: downloads, systemIconName: "arrow.down.circle"))
        }

        if let apps = fm.urls(for: .applicationDirectory, in: .localDomainMask).first {
            list.append(FavoriteLocation(name: "Applications", url: apps, systemIconName: "app.dashed"))
        }

        return list
    }

    public static var mountedVolumes: [FavoriteLocation] {
        let fm = FileManager.default
        var volumes: [FavoriteLocation] = []

        // Root
        volumes.append(FavoriteLocation(name: "Macintosh HD", url: URL(fileURLWithPath: "/"), systemIconName: "internaldrive"))

        // /Volumes
        if let mounted = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeLocalizedNameKey], options: [.skipHiddenVolumes]) {
            for vol in mounted {
                if vol.path != "/" {
                    let name = (try? vol.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? vol.lastPathComponent
                    volumes.append(FavoriteLocation(name: name, url: vol, systemIconName: "externaldrive"))
                }
            }
        }

        return volumes
    }
}
