//
//  Cayena.swift
//  Cayena
//
//  Created by Orjuela Gutierrez, Jorge M. -ND on 2/2/15.
//  Copyright (c) 2015 Orjuela Gutierrez, Jorge M. -ND. All rights reserved.
//

import Foundation

// Cayena errors

public let CayenaErrorDomain = "com.cayena.error"

/*
HTTP supported methods
*/

public enum HTTPMethod: String {
    case DELETE = "DELETE"
    case GET = "GET"
    case OPTIONS = "OPTIONS"
    case POST = "POST"
    case PUT = "PUT"
}


// MARK: Protocols

public protocol Router {
    var baseURL: String { get }
    var encoding: ParametersEncoding { get }
    var headers: [String: String]? { get }
    var method: HTTPMethod { get }
    var parameters: [String: AnyObject]? { get }
    var path: String { get }
    var response: NSData -> (AnyObject?, NSError?) { get }
    var URL: String { get }
}

public protocol URLRequestProtocol {
    var URLRequest: NSURLRequest { get }
}

// MARK: Extensions

extension NSURLRequest: URLRequestProtocol {
    public var URLRequest: NSURLRequest {
        return self
    }
}

public enum ParametersEncoding {
    
    /**
    Uses the associated closure value to construct a new request.
    */
    case Custom ((URLRequestProtocol, [String: AnyObject]?) -> (NSURLRequest, NSError?))
    
    /**
    Create a JSON representation of the parameters object, which is set as the body of the request. The `Content-Type` HTTP header field of an encoded request is set to `application/json`.
    */
    case JSON
    
    /**
    Create a plist representation of the parameters object which is set as the body of the request. The `Content-Type` HTTP header field of an encoded request is set to `application/x-plist`.
    */
    case PropertyList(NSPropertyListFormat, NSPropertyListWriteOptions)
    
    /**
    A query string to be set as or appended to any existing URL query for `GET`, `HEAD`, and `DELETE` requests, or set as the body for requests with any other HTTP method. The `Content-Type` HTTP header field of an encoded request with HTTP body is set to `application/x-www-form-urlencoded`.
    */
    case URL
    
    /**
    Creates a URL request by encoding parameters and applying them onto an existing request.
    
    :param: URLRequest The request to have parameters applied
    :param: parameters The parameters to apply
    
    :returns: A tuple containing the constructed request and the error that occurred during parameter encoding, if any.
    */
    
    public func encode(request: URLRequestProtocol, parameters: [String: AnyObject]?) -> (NSURLRequest, NSError?) {
        if let parameters = parameters {
            let mutableRequest = request.URLRequest.mutableCopy() as! NSMutableURLRequest
            var error: NSError?
            
            switch self {
            case .Custom(let closure):
                return closure(mutableRequest, parameters)
            case .JSON:
                if let data = NSJSONSerialization.dataWithJSONObject(parameters, options: NSJSONWritingOptions.allZeros, error: &error) {
                    mutableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    mutableRequest.HTTPBody = data
                }
            case .PropertyList(let(format, options)):
                if let data = NSPropertyListSerialization.dataWithPropertyList(parameters, format: format, options: options, error: &error) {
                    mutableRequest.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
                    mutableRequest.HTTPBody = data
                }
            case .URL:
                if let httpMethod = HTTPMethod(rawValue: mutableRequest.HTTPMethod) {
                    if isMethodAllowedForParametersInURL(httpMethod) {
                        if let URLComponents = NSURLComponents(URL: mutableRequest.URL!, resolvingAgainstBaseURL: false) {
                            URLComponents.percentEncodedQuery = (URLComponents.percentEncodedQuery == nil ? "" : URLComponents.percentEncodedQuery! + "&") + query(parameters)
                            mutableRequest.URL = URLComponents.URL
                        }
                    } else {
                        if mutableRequest.valueForHTTPHeaderField("Content-Type") == nil {
                            mutableRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        }
                        
                        mutableRequest.HTTPBody = query(parameters).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
                    }
                }
            }
            
            return (mutableRequest, error)
        }
        
        return (request.URLRequest, nil)
    }
    
    func isMethodAllowedForParametersInURL(method: HTTPMethod) -> Bool {
        switch method {
        case .GET, .DELETE:
            return true
        default:
            return false
        }
    }
    
    func createQuery(key: String, _ value: AnyObject) -> [(String, String)] {
        var query: [(String, String)] = []
        if let dictionary = value as? [String: AnyObject] {
            for (nestedKey, nestedValue) in dictionary {
                query.extend(createQuery("\(key)[\(nestedKey)]", nestedValue))
            }
        } else if let array = value as? [AnyObject] {
            for (index, value) in enumerate(array) {
                query.extend(createQuery("\(key)[\(index)]", value))
            }
        } else {
            query.extend([(escape(key), escape("\(value)"))])
        }
        return query;
    }
    
    func escape(string: String) -> String {
        let legalURLCharactersToBeEscaped: CFStringRef = ":/?&=;+!@#$()',*"
        return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as! String
    }
    
    func query(parameters: [String: AnyObject]) -> String {
        var components: [(String, String)] = []
        for key in sorted(Array(parameters.keys), <) {
            if let value: AnyObject = parameters[key] {
                components.extend(createQuery(key, value))
            }
        }
        return join("&", components.map({"\($0)=\($1)"}))
    }
}

// MARK: Manager

/**
Responsible for creating and managing `Request` objects, as well as their underlying `NSURLSession`.
*/

public class Manager {
    
    private enum DownloadType {
        case Request(NSURLRequest)
        case ResumeData(NSData)
    }
    
    private let queue = dispatch_queue_create("com.cayena", DISPATCH_QUEUE_CONCURRENT)
    private let sessionDelegate: SessionDelegate
    
    public var startTaskInmediatly = true
    public let session: NSURLSession
    public class var sharedManager: Manager {
        struct Static {
            static var instance: Manager? = nil
            static var token: dispatch_once_t = 0
        }
        
        dispatch_once(&Static.token, {
            let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
            Static.instance = Manager(configuration: sessionConfiguration)
        })
        return Static.instance!
    }
    
    required public init(configuration: NSURLSessionConfiguration? = nil) {
        sessionDelegate = SessionDelegate()
        session = NSURLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    // MARK: Instance methods
    
    /**
    Creates a task for downloading from the resume data produced from a previous request cancellation.
    
    :param: data The resume data
    :param: destination The closure used to determine the destination of the downloaded file.
    
    :returns: The created download task.
    */
    
    public func download(data: NSData, destination: Task.DownloadDestination) -> Task {
        return downloadTask(.ResumeData(data), destination: destination)
    }
    
    /**
    Creates a task for downloading from the specified request.
    
    :param: request The request
    :param: destination The closure used to determine the destination of the downloaded file.
    
    :returns: The created download task.
    */
    
    public func download(request: URLRequestProtocol, destination: Task.DownloadDestination) -> Task {
        return downloadTask(.Request(request.URLRequest), destination: destination)
    }
    
    /**
    Creates a task for the specified parameters.
    
    :param: method The HTTP method.
    :param: URL The URL string.
    :param: parameters The parameters. `nil` by default.
    :param: parametersEncoding The parameter encoding. `.URL` by default.
    
    :returns: The created task.
    */
    
    public func task(method: HTTPMethod, URL: String, parameters: [String: AnyObject]? = nil, parametersEncoding: ParametersEncoding = .URL) -> Task {
        let mutableRequest = NSMutableURLRequest(URL: NSURL(string: URL)!)
        mutableRequest.HTTPMethod = method.rawValue
        parametersEncoding.encode(mutableRequest, parameters: parameters)
        return task(mutableRequest)
    }
    
    /**
    Creates a task for the specified URL request.
    
    :param: request The URL request
    
    :returns: The created task.
    */
    
    public func task(request: URLRequestProtocol) -> Task {
        var dataTask: NSURLSessionDataTask?
        dispatch_sync(queue, {
            [weak self] in
            dataTask = self?.session.dataTaskWithRequest(request.URLRequest)
        })
        
        let task = Task(session: session, task: dataTask!)
        sessionDelegate.taskDelegates[dataTask!.taskIdentifier] = task.delegate
        if startTaskInmediatly {
            task.resume()
        }
        return task
    }
    
    // MARK: Private methods
    
    private func downloadTask(type: DownloadType, destination: Task.DownloadDestination) -> Task {
        var downloadTask: NSURLSessionDownloadTask?
        switch type {
        case .Request(let request):
            downloadTask = session.downloadTaskWithRequest(request);
        case .ResumeData(let data):
            downloadTask = session.downloadTaskWithResumeData(data)
        }
        
        let task = Task(session: session, task: downloadTask!)
        if let downloadDelegate = task.delegate as? Task.DownloadTaskDelegate {
            downloadDelegate.downloadTaskDidFinishDownloadingToURL = { session, downloadTask, URL in
                return destination(URL, downloadTask.response as! NSHTTPURLResponse)
            }
        }
        
        sessionDelegate.taskDelegates[task.sessionTask.taskIdentifier] = task.delegate
        if startTaskInmediatly {
            task.resume()
        }
        
        return task
    }
}

extension Manager {
    
    // MARK: SessionDelegate
    
    /**
    Responsible for the session delegates.
    */
    
    class SessionDelegate: NSObject, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, NSURLSessionDelegate, NSURLSessionTaskDelegate {
        
        private var taskDelegates: [NSInteger: Task.TaskDelegate] = Dictionary()
        private let queue = dispatch_queue_create("cayena.sessiondelegate", DISPATCH_QUEUE_SERIAL)
        
        var sessionDidBecomeInvalidWithError: ((NSURLSession!, NSError!) -> Void)?
        var sessionDidFinishEventsForBackgroundURLSession: ((NSURLSession!) -> Void)?
        var sessionDidReceiveChallenge: ((NSURLSession!, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential!))?
        
        // MARK: NSURLSessionDelegate
        
        func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
            sessionDidBecomeInvalidWithError?(session, error)
        }
        
        func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
            if let sessionDidReceiveChallenge = sessionDidReceiveChallenge {
                completionHandler(sessionDidReceiveChallenge(session, challenge))
            } else {
                completionHandler(.PerformDefaultHandling, nil)
            }
        }
        
        func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession) {
            sessionDidFinishEventsForBackgroundURLSession?(session)
        }
        
        // MARK: NSURLSessionDataDelegate
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
            if let taskDelegate = delegateFor(dataTask) as? Task.DataTaskDelegate {
                taskDelegate.URLSession(session, dataTask: dataTask, didReceiveResponse: response, completionHandler: completionHandler)
            }
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask) {
            if let taskDelegate = delegateFor(dataTask) as? Task.DataTaskDelegate {
                taskDelegate.URLSession(session, dataTask: dataTask, didBecomeDownloadTask: downloadTask)
            }
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
            if let taskDelegate = delegateFor(dataTask) as? Task.DataTaskDelegate {
                taskDelegate.URLSession(session, dataTask: dataTask, didReceiveData: data)
            }
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, willCacheResponse proposedResponse: NSCachedURLResponse, completionHandler: (NSCachedURLResponse!) -> Void) {
            if let taskDelegate = delegateFor(dataTask) as? Task.DataTaskDelegate {
                taskDelegate.URLSession(session, dataTask: dataTask, willCacheResponse: proposedResponse, completionHandler: completionHandler)
            }
        }
        
        // MARK: NSURLSessionDownloadDelegate
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
            if let taskDelegate = delegateFor(downloadTask) as? Task.DownloadTaskDelegate {
                taskDelegate.URLSession(session, downloadTask: downloadTask, didFinishDownloadingToURL: location)
            }
        }
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if let taskDelegate = delegateFor(downloadTask) as? Task.DownloadTaskDelegate {
                taskDelegate.URLSession(session, downloadTask: downloadTask, didWriteData: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
            }
        }
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
            if let taskDelegate = delegateFor(downloadTask) as? Task.DownloadTaskDelegate {
                taskDelegate.URLSession(session, downloadTask: downloadTask, didResumeAtOffset: fileOffset, expectedTotalBytes: expectedTotalBytes)
            }
        }
        
        // MARK: NSURLSessionTaskDelegate
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, willPerformHTTPRedirection response: NSHTTPURLResponse, newRequest request: NSURLRequest,
            completionHandler: (NSURLRequest!) -> Void) {
                if let taskDelegate = delegateFor(task) {
                    taskDelegate.URLSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
                }
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
            if let taskDelegate = delegateFor(task) {
                taskDelegate.URLSession(session, task: task, didReceiveChallenge: challenge, completionHandler: completionHandler)
            }
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream!) -> Void) {
            if let taskDelegate = delegateFor(task) as? Task.DataTaskDelegate {
                taskDelegate.URLSession(session, task: task, needNewBodyStream: completionHandler)
            }
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            if let taskDelegate = delegateFor(task) as? Task.UploadTaskDelegate {
                taskDelegate.URLSession(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesSent)
            }
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
            if let taskDelegate = delegateFor(task) {
                taskDelegate.URLSession(session, task: task, didCompleteWithError: error)
                taskDelegates[taskDelegate.sessionTask.taskIdentifier] = nil
            }
        }
        
        // MARK: Private methods
        
        private func delegateFor(task: NSURLSessionTask) -> Task.TaskDelegate? {
            var delegate: Task.TaskDelegate?
            dispatch_barrier_sync(queue, {
                [weak self] in
                delegate = self?.taskDelegates[task.taskIdentifier]
                
                })
            return delegate
        }
        
        private func setDelegateFor(task: Task.TaskDelegate) {
            taskDelegates[task.sessionTask.taskIdentifier] = task
        }
    }
}

// MARK: Task

/**
Responsible for start the task and receiving the response.
*/

public class Task {
    
    public typealias DownloadDestination = (NSURL, NSHTTPURLResponse) -> NSURL
    
    private let delegate: TaskDelegate
    private let queue = dispatch_queue_create("com.cayena.task", DISPATCH_QUEUE_CONCURRENT)
    private var sessionTask: NSURLSessionTask {
        return delegate.sessionTask
    }
    
    public let session: NSURLSession
    
    //  The current progress of the task
    public var progress: NSProgress {
        return delegate.progress
    }
    
    //  The current state of the task
    public var state: NSURLSessionTaskState {
        return delegate.sessionTask.state
    }
    
    public required init(session: NSURLSession, task: NSURLSessionTask)  {
        self.session = session
        switch task  {
        case is NSURLSessionDataTask:
            delegate = DataTaskDelegate(task: task)
        case is NSURLSessionDownloadTask:
            delegate = DownloadTaskDelegate(task: task)
        case is NSURLSessionUploadTask:
            delegate = UploadTaskDelegate(task: task)
        default:
            delegate = TaskDelegate(task: task)
        }
    }
    
    // MARK: Instance methods
    
    /**
    Associates an HTTP Basic credential with the request.
    
    :param: user The user.
    :param: password The password.
    
    :returns: The Task.
    */
    
    public func authenticate(#user: String, pasword: String) -> Self {
        let credential = NSURLCredential(user: user, password: pasword, persistence: .ForSession)
        return authenticate(credential: credential)
    }
    
    /**
    Associates a specified credential with the request.
    
    :param: credential The credential.
    
    :returns: The request.
    */
    
    public func authenticate(#credential: NSURLCredential) -> Self {
        delegate.credential = credential
        return self
    }
    
    /**
    Cancels the request.
    */
    public func cancel() {
        if let downloadTaskDelegate = delegate as? DownloadTaskDelegate {
            downloadTaskDelegate.downloadTask.cancelByProducingResumeData { (data) in
                downloadTaskDelegate.resumeData = data
            }
        } else {
            sessionTask.cancel()
        }
    }
    
    /**
    Sets a closure to be called periodically during the lifecycle of the task.
    
    :param: closure The code to be executed periodically during the lifecycle of the request.
    
    :returns: The Task.
    */
    public func progress(closure: ((bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) -> Void)? = nil) -> Self {
        if let downloadDelegate = delegate as? DownloadTaskDelegate {
            downloadDelegate.downloadProgress = closure
        }
        
        return self
    }
    
    /**
    Resumes the request.
    */
    public func resume() {
        sessionTask.resume()
    }
    
    /**
    Suspends the request.
    */
    public func suspend() {
        sessionTask.suspend()
    }
}

extension Task {
    
    // MARK: Response
    
    /**
    Creates return the data response.
    
    :param: completionHandler A closure to be executed once the request has finished.
    
    :return a self instance
    
    */
    
    public func response(completionHandler: (NSURLSessionTask, NSURLResponse?, NSData?, NSError?) -> ())  -> Self {
        response({ data in
            return (data, nil)
            }, completionHandler: completionHandler)
        
        return self
    }
    
    /**
    Creates a JSON response from the response data.
    
    :param: completionHandler A closure to be executed once the request has finished.
    
    :return a self instance
    
    */
    public func JSONResponse(options: NSJSONReadingOptions = .AllowFragments, completionHandler: (NSURLSessionTask, NSURLResponse?, AnyObject?, NSError?) -> ()) -> Self {
        response({ data in
            var error: NSError?
            let JSONObject: AnyObject? = NSJSONSerialization.JSONObjectWithData(data, options: options, error: &error)
            return (JSONObject, error)
            }, completionHandler: completionHandler)
        
        return self
    }
    
    /**
    Creates a Property list response from the response data.
    
    :param: completionHandler A closure to be executed once the request has finished.
    
    :return a self instance
    
    */
    public func propertyListResponse(options: NSPropertyListReadOptions = 0, completionHandler: (NSURLSessionTask, NSURLResponse?, AnyObject?, NSError?) -> ()) -> Self {
        response({ data in
            var error: NSError?
            let propertyListObject: AnyObject? = NSPropertyListSerialization.propertyListWithData(data, options: options, format: nil, error: &error)
            return (propertyListObject, error)
            }, completionHandler: completionHandler)
        
        return self
    }
    
    /**
    Creates a custom response from the response data.
    
    :param: f A function that takes the response data a return a generic value.
    :param: completionHandler A closure to be executed once the request has finished.
    
    :return a self instance
    
    */
    
    public func response<A>(f: NSData -> (A?, NSError?), completionHandler: (NSURLSessionTask, NSURLResponse?, A?, NSError?) -> ()) -> Self {
        dispatch_async(self.delegate.queue, {
            dispatch_async(dispatch_get_main_queue(), {
                var (responseObject: A?, error: NSError?)
                if let data = self.delegate.data {
                    (responseObject, error) = f(data)
                }
                
                completionHandler(self.delegate.sessionTask, self.delegate.sessionTask.response, responseObject, error)
            })
        })
        
        return self
    }
    
    /**
    Creates a string response from the response data.
    
    :param: completionHandler A closure to be executed once the request has finished.
    
    :return a self instance
    
    */
    public func stringResponse(encoding: NSStringEncoding = NSUTF8StringEncoding, completionHandler: (NSURLSessionTask, NSURLResponse?, String?, NSError?) -> ()) -> Self {
        response({ data in
            return (NSString(data: data, encoding: encoding) as? String, nil)
            }, completionHandler: completionHandler)
        
        return self
    }
}

extension Task {
    
    // MARK: Task Delegate
    
    class TaskDelegate: NSObject, NSURLSessionTaskDelegate {
        
        private(set) var error: NSError?
        
        var credential: NSURLCredential?
        var data: NSData? {
            return nil
        }
        let progress = NSProgress(totalUnitCount: 0)
        let queue: dispatch_queue_t
        let sessionTask: NSURLSessionTask
        
        var taskProgress: ((bytesReceived: Int64, bytesWritten: Int64, expectedBytesToWrite: Int64) -> Void)?
        var taskWillPerformHTTPRedirection: ((NSURLSession!, NSURLSessionTask!, NSHTTPURLResponse!, NSURLRequest!) -> (NSURLRequest!))?
        var taskDidReceiveChallenge: ((NSURLSession!, NSURLSessionTask!, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?
        var taskDidSendBodyData: ((NSURLSession!, NSURLSessionTask!, Int64, Int64, Int64) -> Void)?
        var taskNeedNewBodyStream: ((NSURLSession!, NSURLSessionTask!) -> (NSInputStream!))?
        
        init(task: NSURLSessionTask) {
            sessionTask = task
            self.queue = {
                let queue = dispatch_queue_create("com.cayena.task.\(task.taskIdentifier)", DISPATCH_QUEUE_CONCURRENT)
                dispatch_suspend(queue)
                return queue
                }()
        }
        
        // MARK: NSURLSessionTaskDelegate
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
            var disposition: NSURLSessionAuthChallengeDisposition = .PerformDefaultHandling
            var credential: NSURLCredential? = session.configuration.URLCredentialStorage?.defaultCredentialForProtectionSpace(challenge.protectionSpace)
            
            if let taskDidReceiveChallenge = taskDidReceiveChallenge {
                (disposition, credential) = taskDidReceiveChallenge(session, task, challenge)
            } else {
                if challenge.previousFailureCount > 0 {
                    disposition = .CancelAuthenticationChallenge
                } else if (challenge.protectionSpace.authenticationMethod! == NSURLAuthenticationMethodServerTrust) {
                    credential = self.credential ?? NSURLCredential(forTrust: challenge.protectionSpace.serverTrust)
                    if credential != nil {
                        disposition = .UseCredential
                    }
                }
            }
            
            completionHandler(disposition, credential)
            
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
            self.error = error
            dispatch_resume(queue)
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, willPerformHTTPRedirection response: NSHTTPURLResponse, newRequest request: NSURLRequest,
            completionHandler: (NSURLRequest!) -> Void) {
                var redirectionRequest = request
                
                if let taskWillPerformHTTPRedirection = taskWillPerformHTTPRedirection {
                    redirectionRequest = taskWillPerformHTTPRedirection(session, task, response, request)
                }
                
                completionHandler(redirectionRequest)
        }
    }
    
    class DataTaskDelegate: TaskDelegate, NSURLSessionDataDelegate {
        
        private(set) var mutableData = NSMutableData()
        override var data: NSData? {
            return mutableData
        }
        
        var dataTaskDidReceiveResponse: ((NSURLSession!, NSURLSessionDataTask!, NSURLResponse!) -> (NSURLSessionResponseDisposition))?
        var dataTaskDidBecomeDownloadTask: ((NSURLSession!, NSURLSessionDataTask!) -> Void)?
        var dataTaskDidReceiveData: ((NSURLSession!, NSURLSessionDataTask!, NSData!) -> Void)?
        var dataTaskWillCacheResponse: ((NSURLSession!, NSURLSessionDataTask!, NSCachedURLResponse!) -> (NSCachedURLResponse))?
        
        // MARK: NSURLSessionDataDelegate
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
            var responseDisposition: NSURLSessionResponseDisposition = .Allow
            
            if let dataTaskDidReceiveResponse = dataTaskDidReceiveResponse {
                responseDisposition = dataTaskDidReceiveResponse(session, dataTask, response)
            }
            
            completionHandler(responseDisposition)
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask) {
            dataTaskDidBecomeDownloadTask?(session, dataTask)
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
            dataTaskDidReceiveData?(session, dataTask, data)
            mutableData.appendData(data)
            
            if let expectedContentLength =  dataTask.response?.expectedContentLength {
                taskProgress?(bytesReceived: Int64(data.length), bytesWritten: Int64(mutableData.length), expectedBytesToWrite: expectedContentLength)
            }
        }
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream!) -> Void) {
            var bodyStream: NSInputStream?
            
            if taskNeedNewBodyStream != nil {
                bodyStream = taskNeedNewBodyStream!(session, task)
            }
            
            completionHandler(bodyStream)
        }
        
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, willCacheResponse proposedResponse: NSCachedURLResponse, completionHandler: (NSCachedURLResponse!) -> Void) {
            var cachedResponse = proposedResponse
            
            if let dataTaskWillCacheResponse = dataTaskWillCacheResponse {
                cachedResponse = dataTaskWillCacheResponse(session, dataTask, proposedResponse)
            }
            
            completionHandler(cachedResponse)
            
        }
    }
    
    class DownloadTaskDelegate: TaskDelegate, NSURLSessionDownloadDelegate {
        
        var resumeData: NSData?
        var downloadTask: NSURLSessionDownloadTask {
            return sessionTask as! NSURLSessionDownloadTask
        }
        
        var downloadProgress: ((bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) -> Void)?
        var downloadTaskDidFinishDownloadingToURL: ((NSURLSession!, NSURLSessionDownloadTask!, NSURL) -> NSURL)?
        var downloadTaskDidWriteData: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResumeAtOffset: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64) -> Void)?
        
        
        // MARK: NSURLSessionDownloadDelegate
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
            if let downloadTaskDidFinishDownloadingToURL = downloadTaskDidFinishDownloadingToURL {
                let destinationURL = downloadTaskDidFinishDownloadingToURL(session, downloadTask, location)
                NSFileManager.defaultManager().moveItemAtURL(location, toURL: destinationURL, error: &error)
            }
        }
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            progress.totalUnitCount = totalBytesExpectedToWrite
            progress.completedUnitCount = bytesWritten
            downloadProgress?(bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
        
        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
            progress.totalUnitCount = expectedTotalBytes
            progress.completedUnitCount = fileOffset
            downloadTaskDidResumeAtOffset?(session, downloadTask, fileOffset, expectedTotalBytes)
        }
    }
    
    class UploadTaskDelegate: DataTaskDelegate {
        
        var uploadProgress: ((bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) -> Void)?
        
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            progress.totalUnitCount = totalBytesExpectedToSend
            progress.completedUnitCount = totalBytesSent
            uploadProgress?(bytesSent: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }
}

// MARK: Convenience

extension Manager {
    
    func task(router: Router, completionHandler: (NSURLSessionTask, NSURLResponse?, AnyObject?, NSError?) -> Void) -> Task {
        session.configuration.HTTPAdditionalHeaders = router.headers
        return task(router.method, URL: router.URL, parameters: router.parameters, parametersEncoding: router.encoding).response(router.response, completionHandler: completionHandler)
    }
    
}
