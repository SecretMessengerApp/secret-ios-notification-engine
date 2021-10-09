import Foundation
import CoreData
import WireDataModel

public extension NSManagedObjectContext {
    
    func setup(sharedContainerURL: URL, accountUUID: UUID) {
        let accountDirectory = StorageStack.accountFolder(accountIdentifier: accountUUID, applicationContainer: sharedContainerURL)
        let cacheLocation = FileManager.default.cachesURLForAccount(with: accountUUID, in: sharedContainerURL)
        let fileCache = FileAssetCache(location: cacheLocation);
        let avatarCache = ConversationAvatarLocalCache(location: cacheLocation)
        let imageCache = UserImageLocalCache(location: cacheLocation);
        self.performGroupedAndWait { [unowned self] _ in
            self.zm_userImageCache = imageCache
            self.zm_conversationAvatarCache = avatarCache
            self.zm_fileAssetCache = fileCache
            self.setupUserKeyStore(accountDirectory: accountDirectory, applicationContainer: sharedContainerURL)
            ZMUser.selfUser(in: self)
        }
        
    }
    
}
