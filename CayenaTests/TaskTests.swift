//
//  TaskTests.swift
//  Cayena
//
//  Created by Orjuela Gutierrez, Jorge M. -ND on 2/14/15.
//  Copyright (c) 2015 Orjuela Gutierrez, Jorge M. -ND. All rights reserved.
//

import Cayena
import UIKit
import XCTest

class TaskTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatTaskReceiveResponse() {
        let expectation = expectationWithDescription("Task get: http://httpbin.org/get")
        let manager = Cayena.Manager()
        manager.task(.GET, URL: "http://httpbin.org/get")
        .stringResponse { (task, URLResponse, response, error)  in
            XCTAssertNotNil(task, "task should not be nil")
            XCTAssertNotNil(URLResponse, "URLResponse should not be nil")
            XCTAssertNotNil(response, "response should not be nil")
            XCTAssertNil(error, "error should be nil")
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(10, handler: { (error) in
            print("Error ---> \(error)")
        })
    }
    
    func testThatDownloadTask() {
        let expectation: XCTestExpectation = expectationWithDescription("Task download: http://httpbin.org//stream/100")
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).first as! String
        let destination = NSURL(fileURLWithPath: "\(documentsDirectory)/download.txt")!
        let manager = Cayena.Manager()
        
        let request = NSURLRequest(URL: NSURL(string:"http://httpbin.org//stream/\(100)")!)
        manager.download(request, destination: { _, _ in
            return destination
        })
        .response { (_, _, data, error) in
            XCTAssertNil(error, "Error should be nil")
            
            if let data = NSData(contentsOfURL: destination) {
                XCTAssertGreaterThan(data.length, 0, "The file length should be greater than 0")
            } else {
                XCTFail("The file should exists")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(10, handler: { (error) in
            print("Error ---> \(error)")
        })
    }
    
    func testThatDownloadTaskInvokingProgress() {
        let expectation: XCTestExpectation = expectationWithDescription("Task download invoking progress: http://httpbin.org//stream/100")
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).first as! String
        let destination = NSURL(fileURLWithPath: "\(documentsDirectory)/download.txt")!
        let manager = Cayena.Manager()
        
        let request = NSURLRequest(URL: NSURL(string:"http://httpbin.org//stream/\(100)")!)
        let task = manager.download(request, destination: { _, _ in
            return destination
        })
        task.progress { (bytesWritten, totalBytesWritten, totalBytesExpectedToWrite) in
            task.cancel()
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(10, handler: { (error) in
            print("Error ---> \(error)")
        })
    }
}
