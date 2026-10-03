import Foundation
import Security
enum KeychainStore{
 private static let service="com.kleywalker.ElevenSpeak",account="elevenlabs-api-key"
 static func save(_ value:String){let data=Data(value.utf8);let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account];SecItemDelete(q as CFDictionary);var item=q;item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlock;SecItemAdd(item as CFDictionary,nil)}
 static func load()->String?{let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne];var result:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as?Data else{return nil};return String(data:data,encoding:.utf8)}
}
