//
//  ManagerTests.swift
//  Cayena
//
//  Created by Orjuela Gutierrez, Jorge M. -ND on 2/14/15.
//  Copyright (c) 2015 Orjuela Gutierrez, Jorge M. -ND. All rights reserved.
//

import Cayena
import UIKit
import XCTest

class ManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatTaskShouldNotStartInmediatly() {
        let expectation = self.expectationWithDescription("Task should not start")
        Cayena.Manager.sharedManager.startTaskInmediatly = false
        
        let task = Cayena.Manager.sharedManager.task(.GET, URL: "http://httpbin.org/get")
        XCTAssertTrue(task.state == .Suspended, "The task should be suspended")
        
        let request = NSURLRequest(URL: NSURL(string: "http://httpbin.org/get")!)
        Cayena.Manager.sharedManager.task(request).response { (_, _, _, _) in
            expectation.fulfill()
        }.resume()
        
        self.waitForExpectationsWithTimeout(10, handler: { (error)  in
            print("Error ---> \(error)")
        })
    }
}
