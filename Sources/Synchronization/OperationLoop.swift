import Foundation
import CoreData
import WireTransport
import WireRequestStrategy

let contextWasMergedNotification = Notification.Name("zm_contextWasSaved")

private var exLog = ExLog(tag: "OperationLoop")

public class RequestGeneratorStore {

    let requestGenerators: [ZMTransportRequestGenerator]
    private var isTornDown = false

    private let strategies : [AnyObject]

    public init(strategies: [AnyObject]) {

        self.strategies = strategies

        var requestGenerators : [ZMTransportRequestGenerator] = []

        for strategy in strategies {
            if let requestGeneratorSource = strategy as? ZMRequestGeneratorSource {
                for requestGenerator in requestGeneratorSource.requestGenerators {
                    requestGenerators.append({
                        return requestGenerator.nextRequest()
                    })
                }
            }
            if let requestStrategy = strategy as? RequestStrategy {
                requestGenerators.append({
                    requestStrategy.nextRequest()
                })
            }
        }

        self.requestGenerators = requestGenerators
    }

    deinit {
        precondition(isTornDown, "Need to call `tearDown` before deallocating this object")
    }

    public func tearDown() {
        strategies.forEach {
            if $0.responds(to: #selector(ZMObjectSyncStrategy.tearDown)) {
                ($0 as? ZMObjectSyncStrategy)?.tearDown()
            }
        }

        isTornDown = true
    }

    public func nextRequest() -> ZMTransportRequest? {
        for requestGenerator in requestGenerators {
            if let request = requestGenerator() {
                return request
            }
        }

        return nil
    }
}


public class RequestGeneratorObserver {
    
    public var observedGenerator: ZMTransportRequestGenerator? = nil
    
    public func nextRequest() -> ZMTransportRequest? {
        guard let request = observedGenerator?() else { return nil }
        return request
    }
    
}

public class OperationLoop : NSObject, RequestAvailableObserver {
    
    enum ObserverType {
        case newRequest
        case msgNewRequest
        case extensionStreamNewRequest
        case extensionSingleNewRequest
    }

    typealias RequestAvailableClosure = () -> Void
    private let callBackQueue: OperationQueue
    private var tokens: [NSObjectProtocol] = []
    var requestAvailableClosure: RequestAvailableClosure?
    private var moc: NSManagedObjectContext

    init(callBackQueue: OperationQueue = .main, moc: NSManagedObjectContext, type: ObserverType = .newRequest) {
        self.callBackQueue = callBackQueue
        self.moc = moc
        super.init()
        switch type {
        case .newRequest:
            RequestAvailableNotification.addObserver(self)
        case .msgNewRequest:
            RequestAvailableNotification.addMsgObserver(self)
        case .extensionStreamNewRequest:
            RequestAvailableNotification.addExtensionStreamObserver(self)
        case .extensionSingleNewRequest:
            RequestAvailableNotification.addExtensionSingleObserver(self)
        }
    }

    deinit {
        RequestAvailableNotification.removeObserver(self)
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
    
    public func newRequestsAvailable() {
        requestAvailableClosure?()
    }
    
    public func newMsgRequestsAvailable() {}
    
    public func newExtensionStreamRequestsAvailable() {
        requestAvailableClosure?()
    }
    
    public func newExtensionSingleRequestsAvailable() {
        requestAvailableClosure?()
    }

}

public class RequestGeneratingOperationLoop {

    private let operationLoop: OperationLoop!
    private let callBackQueue: OperationQueue
    private var moc: NSManagedObjectContext
    
    private let requestGeneratorStore: RequestGeneratorStore
    private let requestGeneratorObserver: RequestGeneratorObserver
    private unowned let transportSession: ZMBackTransportSession
    

    init(callBackQueue: OperationQueue = .main, requestGeneratorStore: RequestGeneratorStore, transportSession: ZMBackTransportSession,
         moc: NSManagedObjectContext, type: OperationLoop.ObserverType = .newRequest) {
        self.moc = moc
        self.callBackQueue = callBackQueue
        self.requestGeneratorStore = requestGeneratorStore
        self.requestGeneratorObserver = RequestGeneratorObserver()
        self.transportSession = transportSession
        self.operationLoop = OperationLoop(callBackQueue: callBackQueue, moc: moc, type: type)

        operationLoop.requestAvailableClosure = { [weak self] in self?.enqueueRequests() }
        requestGeneratorObserver.observedGenerator = { [weak self] in self?.requestGeneratorStore.nextRequest() }
    }

    deinit {
        transportSession.tearDown()
        requestGeneratorStore.tearDown()
    }
    
    fileprivate func enqueueRequests() {
        var result : ZMTransportEnqueueResult
        
        repeat {
            result = transportSession.attemptToEnqueueSyncRequest(generator: { [weak self] in self?.requestGeneratorObserver.nextRequest() })
        } while result.didGenerateNonNullRequest && result.didHaveLessRequestThanMax
        
    }
}


