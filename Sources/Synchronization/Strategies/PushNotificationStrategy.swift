
import WireRequestStrategy
import WireSyncEngine

public protocol NotificationSessionDelegate: class {
    func modifyNotification(_ alert: ClientNotification)
}

public struct ClientNotification {
    public var title: String
    public var body: String
    public var categoryIdentifier: String
    public var userInfo: [AnyHashable : Any]?
    public var sound: UNNotificationSound?
    public var threadIdentifier: String?
    public var conversationID: String?
    
    public var isInValided: Bool {
        return title.isEmpty && body.isEmpty
    }
}

private var exLog = ExLog(tag: "NotificationExtension")

public final class PushNotificationStrategy: AbstractRequestStrategy, ZMRequestGeneratorSource {
    
    var sync: NotificationSingleSync!
    private weak var eventProcessor: UpdateEventProcessor!
    private weak var delegate: NotificationSessionDelegate?
    private unowned var moc: NSManagedObjectContext!
    
    var eventDecrypter: EventDecrypter!
    private var eventId: String
    private var accountIdentifier: UUID
    
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                notificationSessionDelegate: NotificationSessionDelegate?,
                sharedContainerURL: URL,
                accountIdentifier: UUID,
                eventId: String,
                hugeConvId: String? = nil) {
        
        self.eventId = eventId
        self.accountIdentifier = accountIdentifier
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: nil)
        
        sync = NotificationSingleSync(moc: managedObjectContext, delegate: self, eventId: eventId, hugeConvId: hugeConvId)
        self.eventProcessor = self
        self.delegate = notificationSessionDelegate
        self.moc = managedObjectContext
        self.eventDecrypter = EventDecrypter(syncMOC: managedObjectContext)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return requestGenerators.nextRequest()
    }
    
    public override func nextRequest() -> ZMTransportRequest? {
        return requestGenerators.nextRequest()
    }
    
    public var requestGenerators: [ZMRequestGenerator] {
        return [sync]
    }
    
    deinit {
        exLog.info("PushNotificationStrategy deinit")
    }
    
}

extension PushNotificationStrategy: NotificationSingleSyncDelegate {
    
    public func fetchedEvent(_ event: ZMUpdateEvent) {
        exLog.info("pushNotificationStrategy fetchedEvent \(String(describing: event.uuid?.transportString()))")
        eventProcessor.decryptUpdateEventsAndGenerateNotification([event])
    }
    
    public func failedFetchingEvents() {
        
    }
}

extension PushNotificationStrategy: UpdateEventProcessor {
    
    public func processUpdateEvents(_ updateEvents: [ZMUpdateEvent]) {
        
    }
    
    public func decryptUpdateEventsAndGenerateNotification(_ updateEvents: [ZMUpdateEvent]) {
        exLog.info("ready for decrypt event \(String(describing: updateEvents.first?.uuid?.transportString()))")
        let decryptedUpdateEvents = eventDecrypter.decryptEvents(updateEvents)
        exLog.info("already decrypt event \(String(describing: decryptedUpdateEvents.first?.uuid?.transportString()))")
        let localNotifications = self.convertToLocalNotifications(decryptedUpdateEvents, moc: self.moc)
        exLog.info("convertToLocalNotifications \(String(describing: localNotifications.first.debugDescription))")
        var alert = ClientNotification(title: "", body: "", categoryIdentifier: "")
        if let notification = localNotifications.first {
            alert.title = notification.title ?? ""
            alert.body = notification.body
            alert.categoryIdentifier = notification.category
            alert.sound = UNNotificationSound(named: convertToUNNotificationSoundName(notification.sound.name))
            alert.userInfo = notification.userInfo?.storage
            // only group non ephemeral messages
            if let conversationID = notification.conversationID {
                switch notification.type {
                case .message(.ephemeral): break
                default: alert.conversationID = conversationID.transportString()
                }
            }
        }
        self.delegate?.modifyNotification(alert)
    }
    
    public func storeAndProcessUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
    }
    
}

extension PushNotificationStrategy {
    
    private func convertToLocalNotifications(_ events: [ZMUpdateEvent], moc: NSManagedObjectContext) -> [ZMLocalNotification] {
        return events.compactMap { event in
            var conversation: ZMConversation?
            if let conversationID = event.conversationUUID() {
                exLog.info("convertToLocalNotifications conversationID: \(conversationID) before fetch conversation from coredata")
                conversation = ZMConversation.init(noRowCacheWithRemoteID: conversationID, createIfNeeded: false, in: moc)
                exLog.info("convertToLocalNotifications conversationID: \(conversationID) after fetch conversation from coredata")
            }
            return ZMLocalNotification(noticationEvent: event, conversation: conversation, managedObjectContext: moc)
        }
    }
}
