//
//  ParameterEncodingTests.swift
//  Cayena
//
//  Created by Orjuela Gutierrez, Jorge M. -ND on 2/4/15.
//  Copyright (c) 2015 Orjuela Gutierrez, Jorge M. -ND. All rights reserved.
//

import UIKit
import XCTest

class CustomParametersEncodingTests: XCTestCase {
    
    func testThatEncodeCustomParameters() {
        let expectation = expectationWithDescription("custom encode block should be called")
        let closure: (URLRequestProtocol, [String: AnyObject]?) -> (NSURLRequest, NSError?) = { (URLRequest, parameters) in
            let mutableRequest = URLRequest.URLRequest.mutableCopy() as! NSMutableURLRequest
            mutableRequest.setValue("test", forHTTPHeaderField: "Content-Type")
            expectation.fulfill()
            return (mutableRequest, nil)
        }
        
        let parametersEncoding: ParametersEncoding = .Custom(closure)
        let URLRequest = NSURLRequest(URL: NSURL(string: "http://www.test.com/")!)
        parametersEncoding.encode(URLRequest, parameters: ["foo": "bar"])
        waitForExpectationsWithTimeout(10, handler: { (error) in
            print("Error ---> \(error)")
        })
    }
}

class JSONParametersEncodingTests: XCTestCase {
    
    let parametersEncoding: ParametersEncoding = .JSON
    var URLRequest: NSURLRequest!
    
    override func setUp() {
        super.setUp()
        self.URLRequest = NSURLRequest(URL: NSURL(string: "http://www.test.com/")!)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: JSON encoding tests
    
    func testThatEncodeParametersInJSON() {
        let parameters = ["foo": "bar", "baz": ["a", 1, true], "qux": ["a": 1, "b": [2, 2], "c": [3, 3, 3]]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertNil(error, "error should be nil")
        XCTAssertNil(URLRequest.URL?.query, "query should be nil")
        XCTAssertNotNil(URLRequest.valueForHTTPHeaderField("Content-Type"), "Content-Type should not be nil")
        XCTAssert(URLRequest.valueForHTTPHeaderField("Content-Type")!.hasPrefix("application/json"), "Content-Type should be application/json")
        XCTAssertNotNil(URLRequest.HTTPBody, "HTTPBody should not be nil")
    }
    
    func testThatEncondeNilParametersInJSON() {
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: nil)
        XCTAssertNil(error, "error should be nil")
        XCTAssertNil(URLRequest.valueForHTTPHeaderField("Content-Type"), "Content-Type should be nil")
        XCTAssertNil(URLRequest.HTTPBody, "Body should be nil")
        XCTAssertNil(URLRequest.URL?.query, "Query should be nil")
    }
    
}

class PropertyListParametersEncodingTests: XCTestCase {
    
    let parametersEncoding: ParametersEncoding = .PropertyList(.XMLFormat_v1_0, 0)
    var URLRequest: NSURLRequest!
    
    override func setUp() {
        super.setUp()
        self.URLRequest = NSURLRequest(URL: NSURL(string: "http://www.test.com/")!)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: PropertyList encoding tests
    
    func testThatEncodeParametersInPropertyList() {
        let parameters = ["foo": "bar", "baz": ["a", 1, true], "qux": ["a": 1, "b": [2, 2], "c": [3, 3, 3]]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertNil(error, "error should be nil")
        XCTAssertNil(URLRequest.URL?.query, "query should be nil")
        XCTAssertNotNil(URLRequest.valueForHTTPHeaderField("Content-Type"), "Content-Type should not be nil")
        XCTAssert(URLRequest.valueForHTTPHeaderField("Content-Type")!.hasPrefix("application/x-plist"), "Content-Type should be application/json")
        XCTAssertNotNil(URLRequest.HTTPBody, "HTTPBody should not be nil")
    }
    
    func testThatEncondeNilParametersInPropertyList() {
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: nil)
        XCTAssertNil(error, "error should be nil")
        XCTAssertNil(URLRequest.valueForHTTPHeaderField("Content-Type"), "Content-Type should be nil")
        XCTAssertNil(URLRequest.HTTPBody, "Body should be nil")
        XCTAssertNil(URLRequest.URL?.query, "Query should be nil")
    }
    
}

class URLParametersEncodingTests: XCTestCase {

    let parametersEncoding: ParametersEncoding = .URL
    var URLRequest: NSURLRequest!
    
    override func setUp() {
        super.setUp()
        self.URLRequest = NSURLRequest(URL: NSURL(string: "http://www.test.com/")!)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: URL encoding tests

    func testThatEncodeAndAppendParametersToQuery() {
        let mutableRequest = self.URLRequest.mutableCopy() as! NSMutableURLRequest
        let URLComponents = NSURLComponents(URL: self.URLRequest.URL!, resolvingAgainstBaseURL: false)
        URLComponents?.query = "foo=bar"
        mutableRequest.URL = URLComponents?.URL
        
        let parameters = ["foo1": "bar1"]
        let (URLRequest, error) = self.parametersEncoding.encode(mutableRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo=bar&foo1=bar1", "Invalid query")
    }
    
    func testThatEncodeArrayParametersInURL() {
        let parameters = ["foo": ["bar1", "bar2"]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo%5B0%5D=bar1&foo%5B1%5D=bar2", "Invalid query")
    }
    
    func testThatEncodeBasicParametersInURL() {
        let parameters = ["foo": "bar"]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo=bar", "Invalid query")
    }
    
    func testThatEncodeBooleanParametersInURL() {
        let parameters = ["foo": true]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo=1", "Invalid query")
    }
    
    func testThatEncodeDictionaryParametersInURL() {
        let parameters = ["foo": ["bar1": "bar2"]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo%5Bbar1%5D=bar2", "Invalid query")
    }
    
    func testThatEncodeMixedParamertersInURL() {
        let parameters: [String: AnyObject] = ["foo": "bar", "foo1": [0, 1], "foo2": ["foo3": "bar1"]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo=bar&foo1%5B0%5D=0&foo1%5B1%5D=1&foo2%5Bfoo3%5D=bar1", "Invalid query")
    }
    
    func testThatEncodeNestedDictionaryParametersInURL() {
        let parameters = ["foo": ["foo1": ["bar": 1]]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo%5Bfoo1%5D%5Bbar%5D=1", "Invalid query")
    }
    
    func testThatEncodeNestedDictionaryWithArrayValueParametersInURL() {
        let parameters = ["foo": ["foo1": ["bar": [1, 2, 4]]]]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo%5Bfoo1%5D%5Bbar%5D%5B0%5D=1&foo%5Bfoo1%5D%5Bbar%5D%5B1%5D=2&foo%5Bfoo1%5D%5Bbar%5D%5B2%5D=4", "Invalid query")
    }
    
    func testThatEncondeNilParametersInURL() {
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: nil)
        XCTAssertNil(URLRequest.URL!.query, "Query should be nil")
    }
    
    func testThatEncodePercentParamertersInURL() {
        let parameters = ["foo": "%bar"]
        let (URLRequest, error) = self.parametersEncoding.encode(self.URLRequest, parameters: parameters)
        XCTAssertEqual(URLRequest.URL!.query!, "foo=%25bar", "Invalid query")
    }
    
}
