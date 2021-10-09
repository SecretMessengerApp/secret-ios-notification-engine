
import Foundation
import WireDataModel
import WireTransport
import WireRequestStrategy
import WireLinkPreview

public class SaveNotificationSession {
    
    public let transportSession: ZMBackTransportSession
    
    private var syncMoc: NSManagedObjectContext!
        
    private let operationLoop: RequestGeneratingOperationLoop
    
    private let saveNotificationPersistence: ContextDidSaveNotificationPersistence
    
    private let sharedContainerURL: URL
    
    private let accountIdentifier: UUID
    
    private var strategy: PushSaveNotificationStrategy
    
    public convenience init(applicationGroupIdentifier: String,
                            accountIdentifier: UUID,
                            environment: BackendEnvironmentProvider,
                            token: ZMAccessToken?,
                            delegate: SaveNotificationSessionDelegate) throws {
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
            moc.stalenessInterval = -1
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
            sharedContainerURL: sharedContainerURL,
            accountIdentifier: accountIdentifier,
            delegate: delegate)
    }
    
    public convenience init(moc: NSManagedObjectContext,
                            transportSession: ZMBackTransportSession,
                            accountContainer: URL,
                            sharedContainerURL: URL,
                            accountIdentifier: UUID,
                            delegate: SaveNotificationSessionDelegate) throws {
        

        let stage = PushSaveNotificationStrategy(withManagedObjectContext: moc, sharedContainerURL: sharedContainerURL, accountIdentifier: accountIdentifier, delegate:delegate)
        
        let requestGeneratorStore = RequestGeneratorStore(strategies: [stage])
        
        let operationLoop = RequestGeneratingOperationLoop(
            callBackQueue: .main,
            requestGeneratorStore: requestGeneratorStore,
            transportSession: transportSession,
            moc:moc,
            type: .extensionStreamNewRequest
        )
        
        try self.init(
            moc: moc,
            transportSession: transportSession,
            operationLoop: operationLoop,
            sharedContainerURL: sharedContainerURL,
            accountIdentifier: accountIdentifier,
            stage: stage
        )
        
    }
    
    internal init(moc: NSManagedObjectContext,
                  transportSession: ZMBackTransportSession,
                  operationLoop: RequestGeneratingOperationLoop,
                  sharedContainerURL: URL,
                  accountIdentifier: UUID,
                  stage: PushSaveNotificationStrategy
        ) throws {
        
        self.syncMoc = moc
        self.transportSession = transportSession
        self.operationLoop = operationLoop
        self.sharedContainerURL = sharedContainerURL
        self.accountIdentifier = accountIdentifier
        self.strategy = stage
        let accountContainer = StorageStack.accountFolder(accountIdentifier: accountIdentifier, applicationContainer: sharedContainerURL)
        self.saveNotificationPersistence = ContextDidSaveNotificationPersistence(accountContainer: accountContainer)
        NotificationCenter.default.addObserver(
        self,
        selector: #selector(SaveNotificationSession.contextDidSave(_:)),
        name:.NSManagedObjectContextDidSave,
        object: moc)
    }

    deinit {
        print("NotificationSession deinit")
        transportSession.reachability.tearDown()
        transportSession.tearDown()
    }
}

extension SaveNotificationSession {
    @objc func contextDidSave(_ note: Notification){
        self.saveNotificationPersistence.add(note)
    }
}
