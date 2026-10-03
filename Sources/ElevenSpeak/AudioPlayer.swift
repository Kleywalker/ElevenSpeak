import AVFoundation
final class AudioPlayer:NSObject,AVAudioPlayerDelegate{
 private var player:AVAudioPlayer?;private var completion:(()->Void)?
 func play(data:Data,completion:(()->Void)?)throws{stop();self.completion=completion;let p=try AVAudioPlayer(data:data);p.delegate=self;p.prepareToPlay();p.play();player=p}
 func stop(){player?.stop();player=nil;completion=nil}
 func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool){self.player=nil;completion?();completion=nil}
}
