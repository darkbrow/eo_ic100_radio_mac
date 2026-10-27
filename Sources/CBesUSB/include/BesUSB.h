#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 삼성 EO-IC100(VID 0x04e8, PID 0xa054/0xa059/0xa05b)의 기본 컨트롤 엔드포인트로
/// 벤더 요청(장치→호스트)을 보내는 얇은 래퍼.
/// 인터페이스를 점유(detach/claim)하지 않으므로 macOS 오디오 드라이버와 충돌하지 않는다.
@interface BesUSB : NSObject

/// 지원하는 장치가 연결되어 있는지 확인한다(열지 않음).
+ (BOOL)isPresent;
/// 연결된 장치의 제품 ID. 없으면 0.
+ (uint16_t)presentProductID;
/// 연결된 장치의 USB 제품 이름("USB Product Name"). 없으면 nil.
+ (nullable NSString *)presentProductName;
/// 시스템에 보이는 모든 USB 장치를 "VID:PID 이름"으로 나열한 진단용 문자열.
+ (NSString *)diagnosticReport;

/// 장치를 찾아 연다. 없거나 열 수 없으면 nil과 에러.
/// (initWithError: 대신 팩토리 메서드를 쓴다 — Swift에서 NSObject.init()과 겹치지 않도록)
+ (nullable instancetype)openDevice:(NSError **)error NS_SWIFT_NAME(openDevice());

@property (nonatomic, readonly) uint16_t productID;

/// bmRequestType 0xC0(벤더, 장치→호스트) 컨트롤 요청.
- (nullable NSData *)controlInRequest:(uint8_t)request
                                value:(uint16_t)value
                                index:(uint16_t)index
                               length:(uint16_t)length
                                error:(NSError **)error
    NS_SWIFT_NAME(controlIn(request:value:index:length:));

- (void)close;

@end

NS_ASSUME_NONNULL_END
