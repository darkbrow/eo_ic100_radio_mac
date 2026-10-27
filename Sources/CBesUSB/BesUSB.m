#import "BesUSB.h"
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>

static const uint32_t kVendorID = 0x04e8;

static BOOL IsSupportedProduct(uint32_t pid) {
    return pid == 0xa054 || pid == 0xa059 || pid == 0xa05b;
}

static NSError *MakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"BesUSB"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSNumber *NumberProperty(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    NSObject *object = (__bridge_transfer NSObject *)value;
    return [object isKindOfClass:[NSNumber class]] ? (NSNumber *)object : nil;
}

static NSString *StringProperty(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    NSObject *object = (__bridge_transfer NSObject *)value;
    return [object isKindOfClass:[NSString class]] ? (NSString *)object : nil;
}

/// 모든 USB 장치 서비스를 순회한다. visit가 YES를 반환하면 멈춘다.
/// 장치를 남겨 두려면 visit 안에서 IOObjectRetain 해야 한다.
/// 매칭 딕셔너리에 vendor/product를 넣지 않고 레지스트리 값을 직접 비교한다 (libusb와 같은 방식).
static void EnumerateUSBDevices(BOOL (^visit)(io_service_t service)) {
    static const char *classNames[] = {"IOUSBHostDevice", "IOUSBDevice"};
    for (size_t i = 0; i < 2; i++) {
        CFMutableDictionaryRef match = IOServiceMatching(classNames[i]);
        if (match == NULL) {
            continue;
        }
        io_iterator_t iterator = IO_OBJECT_NULL;
        // 딕셔너리 참조는 이 호출이 소비한다.
        if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) != KERN_SUCCESS) {
            continue;
        }
        BOOL any = NO;
        BOOL stop = NO;
        io_service_t service;
        while (!stop && (service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
            any = YES;
            stop = visit(service);
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
        if (any) {
            return;
        }
    }
}

/// 지원 장치의 서비스를 반환한다. 호출자가 IOObjectRelease 해야 한다.
static io_service_t FindService(uint16_t *outProductID, NSString **outName) {
    __block io_service_t found = IO_OBJECT_NULL;
    __block uint16_t foundPID = 0;
    __block NSString *foundName = nil;
    EnumerateUSBDevices(^BOOL(io_service_t service) {
        NSNumber *vendor = NumberProperty(service, CFSTR("idVendor"));
        NSNumber *product = NumberProperty(service, CFSTR("idProduct"));
        if (vendor != nil && product != nil
            && vendor.unsignedIntValue == kVendorID
            && IsSupportedProduct(product.unsignedIntValue)) {
            IOObjectRetain(service);
            found = service;
            foundPID = (uint16_t)product.unsignedIntValue;
            foundName = StringProperty(service, CFSTR("USB Product Name"));
            return YES;
        }
        return NO;
    });
    if (outProductID) {
        *outProductID = foundPID;
    }
    if (outName) {
        *outName = foundName;
    }
    return found;
}

@implementation BesUSB {
    IOUSBHostDevice *_device;
    uint16_t _productID;
}

+ (BOOL)isPresent {
    return [self presentProductID] != 0;
}

+ (uint16_t)presentProductID {
    uint16_t pid = 0;
    io_service_t service = FindService(&pid, NULL);
    if (service != IO_OBJECT_NULL) {
        IOObjectRelease(service);
    }
    return pid;
}

+ (nullable NSString *)presentProductName {
    NSString *name = nil;
    io_service_t service = FindService(NULL, &name);
    if (service != IO_OBJECT_NULL) {
        IOObjectRelease(service);
    }
    return name;
}

+ (NSString *)diagnosticReport {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    __block NSUInteger total = 0;
    EnumerateUSBDevices(^BOOL(io_service_t service) {
        total += 1;
        if (lines.count < 60) {
            NSNumber *vendor = NumberProperty(service, CFSTR("idVendor"));
            NSNumber *product = NumberProperty(service, CFSTR("idProduct"));
            NSString *name = StringProperty(service, CFSTR("USB Product Name")) ?: @"(이름 없음)";
            BOOL supported = vendor != nil && product != nil
                && vendor.unsignedIntValue == kVendorID
                && IsSupportedProduct(product.unsignedIntValue);
            [lines addObject:[NSString stringWithFormat:@"%@ %04x:%04x %@",
                              supported ? @"*" : @" ",
                              vendor.unsignedIntValue,
                              product.unsignedIntValue,
                              name]];
        }
        return NO;
    });
    NSString *header = [NSString stringWithFormat:
        @"USB 장치 %lu개 (* = EO-IC100으로 인식, 찾는 ID는 04e8:a054 / a059 / a05b)",
        (unsigned long)total];
    return [[@[header] arrayByAddingObjectsFromArray:lines] componentsJoinedByString:@"\n"];
}

+ (nullable instancetype)openDevice:(NSError **)error {
    uint16_t pid = 0;
    io_service_t service = FindService(&pid, NULL);
    if (service == IO_OBJECT_NULL) {
        if (error) {
            *error = MakeError(1, @"EO-IC100을 찾을 수 없습니다.");
        }
        return nil;
    }
    NSError *openError = nil;
    // 옵션 0: 장치를 캡처하지 않고 컨트롤 요청만 보낸다.
    IOUSBHostDevice *device = [[IOUSBHostDevice alloc] initWithIOService:service
                                                                  options:(IOUSBHostObjectInitOptions)0
                                                                    queue:nil
                                                                    error:&openError
                                                           interestHandler:nil];
    IOObjectRelease(service);
    if (device == nil) {
        if (error) {
            *error = openError ?: MakeError(2, @"EO-IC100을 열 수 없습니다.");
        }
        return nil;
    }
    BesUSB *usb = [[self alloc] init];
    usb->_device = device;
    usb->_productID = pid;
    return usb;
}

- (uint16_t)productID {
    return _productID;
}

- (nullable NSData *)controlInRequest:(uint8_t)request
                                value:(uint16_t)value
                                index:(uint16_t)index
                               length:(uint16_t)length
                                error:(NSError **)error {
    if (_device == nil) {
        if (error) {
            *error = MakeError(3, @"장치가 열려 있지 않습니다.");
        }
        return nil;
    }
    IOUSBDeviceRequest req;
    req.bmRequestType = 0xC0;  // 장치→호스트 | 벤더 | 장치
    req.bRequest = request;
    req.wValue = value;
    req.wIndex = index;
    req.wLength = length;

    NSMutableData *data = [NSMutableData dataWithLength:length];
    NSUInteger transferred = 0;
    NSError *sendError = nil;
    BOOL ok = [_device sendDeviceRequest:req
                                    data:data
                        bytesTransferred:&transferred
                       completionTimeout:1.0
                                   error:&sendError];
    if (!ok) {
        if (error) {
            *error = sendError ?: MakeError(4, @"컨트롤 전송에 실패했습니다.");
        }
        return nil;
    }
    return [data subdataWithRange:NSMakeRange(0, MIN(transferred, data.length))];
}

- (void)close {
    [_device destroy];
    _device = nil;
}

- (void)dealloc {
    [self close];
}

@end
