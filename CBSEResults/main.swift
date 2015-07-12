//
//  main.swift
//  CBSEResults
//
//  Created by Deepanshu Utkarsh on 05/07/15.
//  Copyright (c) 2015 Forked. All rights reserved.
//

/*
Roll numbers run
1600001 till 1719685
2600001 till 2764100
3600001 till 3647565
4600001 till 4652913
5600001 till 5691383
5800001 till 5917335
6600001 till 6648925
7600001 till 7682109
9100001 till 9209884
9600001 till 9770351
*/

import Foundation
import AppKit

struct Log {
    var rate: Double? { didSet { log() } }
    var completion: Double? { didSet { log() } }
    var fetchedResults: Int? { didSet { log() } }
    var totalResults: Int? { didSet { log() } }
    
    mutating func log() {
        if rate != nil && completion != nil && fetchedResults != nil && totalResults != nil {
            objc_sync_enter(rate)
            objc_sync_enter(completion)
            objc_sync_enter(fetchedResults)
            objc_sync_enter(totalResults)
            NSLog("%.2f%% (\(fetchedResults!)/\(totalResults!)), \(rate!) results/s, ETA %.2fm", completion!, (Double(totalResults! - fetchedResults!) / (60 * rate!)))
            rate = nil
            completion = nil
            fetchedResults = nil
            totalResults = nil
            objc_sync_exit(rate)
            objc_sync_exit(completion)
            objc_sync_exit(fetchedResults)
            objc_sync_exit(totalResults)
        }
    }
}

var log = Log()

extension String {
    func trim() -> String {
        var s = self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        return s
    }
}

extension NSURLSession {
    static private var lastPrintTime = 0.0
    static private var rates = [0.0]
    
    func countedDataTaskWithRequest(request: NSURLRequest, completionHandler: ((NSData!, NSURLResponse!, NSError!) -> Void)?) -> NSURLSessionDataTask {
        var lastPrintTime = NSURLSession.lastPrintTime
        var rates = NSURLSession.rates
        if CACurrentMediaTime() > lastPrintTime + 1 {
            log.rate = rates.reduce(0) { $0 + $1 } / Double(rates.count)
            lastPrintTime = CACurrentMediaTime()
            
            rates.append(0)
        }
        else {
            rates.append(rates.removeLast() + 1)
        }
        if rates.count > 5 {
            rates.removeAtIndex(0)
        }
        NSURLSession.lastPrintTime = lastPrintTime
        NSURLSession.rates = rates
        return self.dataTaskWithRequest(request, completionHandler: completionHandler)
    }
}

let ranges: [Range<Int>] = [1600001...1719685, // explicit type because type inference in large arrays causes SourceKitService crash
    2600001...2764100,
    3600001...3647565,
    4600001...4652913,
    5600001...5691383,
    5800001...5917335,
    6600001...6648925,
    7600001...7682109,
    9100001...9209884,
    9600001...9770351]

var queue = NSOperationQueue()

for (index, range) in enumerate(ranges) {
    queue.addOperation(NSBlockOperation(block: { () -> Void in
        var req = NSMutableURLRequest(URL: NSURL(string: "http://cbseresults.nic.in/class12/cbse122015_all.asp")!, cachePolicy: NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.HTTPMethod = "POST"
        req.setValue("http://cbseresults.nic.in/class12/cbse122015_all.htm", forHTTPHeaderField: "Referer")
        
        var resultsPath = String(format: "~/Desktop/Results/result%d.txt", index).stringByExpandingTildeInPath
        var indexPath = String(format: "~/Desktop/Results/index%d.txt", index).stringByExpandingTildeInPath
        
        if !NSFileManager.defaultManager().fileExistsAtPath(resultsPath) {
            NSFileManager.defaultManager().createFileAtPath(resultsPath, contents: nil, attributes: nil)
        }
        
        var fileHandle = NSFileHandle(forWritingAtPath: resultsPath)!
        fileHandle.seekToEndOfFile()
        
        var startIndex = String(contentsOfFile: String(format: "~/Desktop/Results/index%d.txt", index).stringByExpandingTildeInPath, encoding: NSUTF8StringEncoding, error: nil)?.toInt()
        if startIndex == 0 {
            startIndex = range.startIndex
        }
        
        for rollNumber in range {
            if rollNumber < startIndex {
                continue
            }
            req.HTTPBody = String(format: "regno=%d", rollNumber).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
            
            var semaphore = dispatch_semaphore_create(0)
            
            var data: NSData?
            
            while data == nil {
                NSURLSession.sharedSession().countedDataTaskWithRequest(req, completionHandler: { (newData, resp, err) -> Void in
                    data = newData
                    dispatch_semaphore_signal(semaphore)
                }).resume()
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW as dispatch_time_t, Int64(5 * NSEC_PER_SEC)))
            }
            
            autoreleasepool {
                var buffer = [UInt8](count:data!.length, repeatedValue:0)
                data!.getBytes(&buffer, length:data!.length)
                var html = String(bytes: buffer, encoding: NSASCIIStringEncoding)
                
                var e: NSError?
                var parser = HTMLParser(html: html!, encoding: NSUTF8StringEncoding, option: CInt(HTML_PARSE_RECOVER.value | HTML_PARSE_NOERROR.value), error: &e)
                
                if parser.htmlString.rangeOfString("Result Not Found") != nil {
                    return
                }
                
                var subCodes = parser.html!.xpath("//center/table/tr[position()>1]/td[position()=1 and @align='middle' and ./font/text()!='500' and ./font/text()!='501' and ./font/text()!='502' and ./font/text()!='503' and ./font/text()!='504']/font")!
                var subNames = parser.html!.xpath("//center/table/tr[position()>1]/td[position()=2 and ../td[position()=1 and @align='middle' and ./font/text()!='500' and ./font/text()!='501' and ./font/text()!='502' and ./font/text()!='503' and ./font/text()!='504']]/font")!
                var theory = parser.html!.xpath("//center/table/tr[position()>1]/td[position()=3 and ../td[position()=1 and @align='middle' and ./font/text()!='500' and ./font/text()!='501' and ./font/text()!='502' and ./font/text()!='503' and ./font/text()!='504']]/font")!
                var practical = parser.html!.xpath("//center/table/tr[position()>1]/td[position()=4 and ../td[position()=1 and @align='middle' and ./font/text()!='500' and ./font/text()!='501' and ./font/text()!='502' and ./font/text()!='503' and ./font/text()!='504']]/font")!
                
                var student = [String: AnyObject]()
                student["name"] = parser.html!.xpath("//table[5]/tr[2]/td[2]//b")!.first!.contents
                student["roll"] = rollNumber
                var subjects = [[String: String]]()
                
                for (index, node: HTMLNode) in enumerate(subCodes) {
                    var subject = ["code": node.contents.trim(), "name": subNames[index].contents.trim(), "theory": theory[index].contents.trim()]
                    if practical[index].contents.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) != 0 {
                        subject["prac"] = practical[index].contents
                    }
                    subjects.append(subject)
                }
                
                student["subs"] = subjects
                
                fileHandle.writeData(NSJSONSerialization.dataWithJSONObject(student, options: nil, error: nil)!)
            }
            fileHandle.writeData("\n".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
            
            "\(rollNumber + 1)".writeToFile(indexPath, atomically: true, encoding: NSUTF8StringEncoding, error: nil)
            
            if true {
                log.fetchedResults = rollNumber
                log.completion = 100.0 * Double(rollNumber - range.startIndex) / Double(range.endIndex - range.startIndex)
                log.totalResults = range.endIndex
            }
        }
    }))
}

queue.waitUntilAllOperationsAreFinished()
