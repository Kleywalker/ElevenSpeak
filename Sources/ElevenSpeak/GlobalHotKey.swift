import AppKit
import Carbon.HIToolbox
final class GlobalHotKey{
 private var ref:EventHotKeyRef?;private var handler:(()->Void)?
 func registerOptionEscape(handler:@escaping()->Void){self.handler=handler;var id=EventHotKeyID(signature:OSType(0x4553504B),id:1);RegisterEventHotKey(UInt32(kVK_Escape),UInt32(optionKey),id,GetApplicationEventTarget(),0,&ref);var installed:EventHandlerRef?;var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed));InstallEventHandler(GetApplicationEventTarget(),{_,_,userData in guard let userData else{return noErr};Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().handler?();return noErr},1,&spec,Unmanaged.passUnretained(self).toOpaque(),&installed)}
 deinit{if let ref{UnregisterEventHotKey(ref)}}
}
