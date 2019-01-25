import XCTest

import DeepLearningTests
import MNISTTests

var tests = [XCTestCaseEntry]()
tests += DeepLearningTests.allTests()
// tests += MNISTTests.allTests()
XCTMain(tests)
