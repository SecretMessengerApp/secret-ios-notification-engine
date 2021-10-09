
import Foundation
import WireDataModel
import WireTransport
import WireRequestStrategy
import WireLinkPreview


extension BackendEnvironmentProvider {
    func cookieStorage(for account: Account) -> ZMPersistentCookieStorage {
        let backendURL = self.backendURL.host!
        return ZMPersistentCookieStorage(forServerName: backendURL, userIdentifier: account.userIdentifier)
    }
    
    public func isAuthenticated(_ account: Account) -> Bool {
        return cookieStorage(for: account).authenticationCookieData != nil
    }
}

private var exLog = ExLog(tag: "NotificationSession")


public class NotificationSession {
    
    public let transportSession: ZMBackTransportSession
    
    public var syncMoc: NSManagedObjectContext!
    
    public var lastEventId: UUID?
        
    private let operationLoop: RequestGeneratingOperationLoop
    
    private var saveNotificationPersistence: ContextDidSaveNotificationPersistence
    
    public convenience init(applicationGroupIdentifier: String,
                            accountIdentifier: UUID,
                            environment: BackendEnvironmentProvider,
                            delegate: NotificationSessionDelegate?,
                            token: ZMAccessToken?,
                            eventId: String,
                            hugeConvId: String? = nil) throws {
       
        let sharedContainerURL = FileManager.sharedContainerDirectory(for: applicationGroupIdentifier)
        
        let accountDirectory = StorageStack.accountFolder(accountIdentifier: accountIdentifier, applicationContainer: sharedContainerURL)
        
        let storeFile = accountDirectory.appendingPersistentStoreLocation()
        let model = NSManagedObjectModel.loadModel()
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options = NSPersistentStoreCoordinator.persistentStoreOptions(supportsMigration: false)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeFile, options: options)
        let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        moc.performAndWait {
            moc.persistentStoreCoordinator = psc
            moc.setup(sharedContainerURL: sharedContainerURL, accountUUID: accountIdentifier)
        }
        let cookieStorage = ZMPersistentCookieStorage(forServerName: environment.backendURL.host!, userIdentifier: accountIdentifier)
        let reachabilityGroup = ZMSDispatchGroup(dispatchGroup: DispatchGroup(), label: "Sharing session reachability")!
        let serverNames = [environment.backendURL, environment.backendWSURL].compactMap { $0.host }
        let reachability = ZMReachability(serverNames: serverNames, group: reachabilityGroup)
        
        let transportSession = ZMBackTransportSession(
            environment: environment,
            cookieStorage: cookieStorage,
            reachability: reachability,
            initialAccessToken: token,
            applicationGroupIdentifier: applicationGroupIdentifier
        )
        
        try self.init(
            moc: moc,
            transportSession: transportSession,
            accountContainer: StorageStack.accountFolder(accountIdentifier: accountIdentifier, applicationContainer: sharedContainerURL),
            delegate: delegate,
            sharedContainerURL: sharedContainerURL,
            accountIdentifier: accountIdentifier,
            eventId: eventId,
            hugeConvId: hugeConvId)
    }
    
    public convenience init(moc: NSManagedObjectContext,
                            transportSession: ZMBackTransportSession,
                            accountContainer: URL,
                            delegate: NotificationSessionDelegate?,
                            sharedContainerURL: URL,
                            accountIdentifier: UUID,
                            eventId: String,
                            hugeConvId: String? = nil) throws {
        
        let stage = PushNotificationStrategy(withManagedObjectContext: moc, notificationSessionDelegate: delegate, sharedContainerURL: sharedContainerURL, accountIdentifier: accountIdentifier, eventId: eventId, hugeConvId: hugeConvId)
        
        let requestGeneratorStore = RequestGeneratorStore(strategies: [stage])
        
        let operationLoop = RequestGeneratingOperationLoop(
            callBackQueue: .main,
            requestGeneratorStore: requestGeneratorStore,
            transportSession: transportSession,
            moc: moc,
            type: .extensionSingleNewRequest
        )
        
        let isHuge = hugeConvId != nil
        
        try self.init(
            moc: moc,
            transportSession: transportSession,
            operationLoop: operationLoop,
            sharedContainerURL: sharedContainerURL,
            accountContainer: accountContainer,
            accountIdentifier: accountIdentifier,
            isHuge: isHuge
        )
        
    }
    
    internal init(moc: NSManagedObjectContext,
                  transportSession: ZMBackTransportSession,
                  operationLoop: RequestGeneratingOperationLoop,
                  sharedContainerURL: URL,
                  accountContainer: URL,
                  accountIdentifier: UUID,
                  isHuge: Bool = false
    ) throws {
        self.syncMoc = moc
        self.transportSession = transportSession
        self.operationLoop = operationLoop
        self.saveNotificationPersistence = ContextDidSaveNotificationPersistence(accountContainer: accountContainer)
        moc.performAndWait { [unowned self] in
            self.lastEventId = isHuge ? moc.zm_lastHugeNotificationID : moc.zm_lastNotificationID
        }
        NotificationCenter.default.addObserver(
        self,
        selector: #selector(NotificationSession.contextDidSave(_:)),
        name:.NSManagedObjectContextDidSave,
        object: moc)
    }

    deinit {
        exLog.info("NotificationSession deinit")
        transportSession.reachability.tearDown()
        transportSession.tearDown()
    }
}

extension NotificationSession {
    @objc func contextDidSave(_ note: Notification){
        self.saveNotificationPersistence.add(note)
    }
}
