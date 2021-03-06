//
//  DemoViewController.m
//  PublishDemo
//
//  Created by liwenlong on 15/10/9.
//  Copyright (c) 2015年 vhall. All rights reserved.
//

#if VHallFilterSDK_ENABLE
#import "VHallLivePublishFilter.h"
#else
#endif
#import "LaunchLiveViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "UIAlertView+ITTAdditions.h"
#import "MBProgressHUD.h"
#import "WatchLiveOnlineTableViewCell.h"
#import "WatchLiveChatTableViewCell.h"
#import "VHallApi.h"

#import "VHLiveChatView.h"
#import "VHMessageToolView.h"


#if VHallFilterSDK_ENABLE
@interface LaunchLiveViewController ()<CameraEngineRtmpDelegate, VHallChatDelegate, VHallLivePublishFilterDelegate,VHMessageToolBarDelegate>
#else
@interface LaunchLiveViewController ()<CameraEngineRtmpDelegate, VHallChatDelegate,VHMessageToolBarDelegate>
#endif
{
    BOOL  _isVideoStart;
    BOOL  _isAudioStart;
    BOOL  _torchType;
    BOOL  _onlyVideo;
    BOOL  _isFontVideo;
    MBProgressHUD * _hud;
    UIButton * _lastFilterSelectBtn;

    VHallChat         *_chat;       //聊天
    dispatch_source_t _timer;
    long              _liveTime;
}

#if VHallFilterSDK_ENABLE
@property (strong, nonatomic)VHallLivePublishFilter *engine;
#else
@property (strong, nonatomic)VHallLivePublish *engine;
#endif
@property (weak, nonatomic) IBOutlet UIView *perView;
@property (weak, nonatomic) IBOutlet UIImageView *logView;
@property (weak, nonatomic) IBOutlet UILabel *bitRateLabel;
@property (weak, nonatomic) IBOutlet UIButton *videoStartAndStopBtn;
@property (weak, nonatomic) IBOutlet UIButton *audioStartAndStopBtn;
@property (weak, nonatomic) IBOutlet UIButton *torchBtn;
@property (weak, nonatomic) IBOutlet UIView *chatContainerView;
@property (weak, nonatomic) IBOutlet UITextField *msgTextField;
@property (weak, nonatomic) IBOutlet UIButton *chatMsgSend;
@property (weak, nonatomic) IBOutlet UIButton *filterBtn;
@property (weak, nonatomic) IBOutlet UIView *filterView;
@property (weak, nonatomic) IBOutlet UIButton *defaultFilterSelectBtn;
@property (weak, nonatomic) IBOutlet UIButton *closeBtn;
@property (weak, nonatomic) IBOutlet UIView *infoView;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UIButton *hideKeyBtn;

@property (nonatomic, strong) VHLiveChatView *chatView;
@property (nonatomic, strong) NSMutableArray *chatDataArray;
@property (nonatomic,strong) VHMessageToolView * messageToolView;  //输入框
@end

@implementation LaunchLiveViewController

#pragma mark -
#pragma mark - Lifecycle
- (id)init
{
    self = [super initWithNibName:NSStringFromClass([self class]) bundle:meetingResourcesBundle];
    if (self) {
        [self initDatas];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self initViews];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //初始化CameraEngine
    [self initCameraEngine];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    if (_chat) {
        _chat = nil;
    }
    
    if (_engine) {
        _engine = nil;
    }
    
    //允许iOS设备锁屏
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    [self.view removeObserver:self forKeyPath:kViewFramePath];
    [[NSNotificationCenter defaultCenter]removeObserver:self];
    VHLog(@"%@ dealloc",[[self class]description]);
}

-(void)LaunchLiveWillResignActive
{
    [_engine disconnect];
}

-(void)LaunchLiveDidBecomeActive
{
    [_engine reconnect];
}

- (IBAction)closeBtnClick:(id)sender
{
    if (_engine.isPublishing)
    {
         [_engine stopLive];//停止活动
    }
   
    [self dismissViewControllerAnimated:YES completion:^{
    }];
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark - Lifecycle(Private)

- (void)registerLiveNotification
{
    [self.view addObserver:self forKeyPath:kViewFramePath options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(LaunchLiveWillResignActive)name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(LaunchLiveDidBecomeActive)name:UIApplicationDidBecomeActiveNotification object:nil];
}

-(void)initDatas
{
    _isVideoStart = NO;
    _isAudioStart = NO;
    _torchType = NO;
    _onlyVideo = NO;
    _isFontVideo = NO;
    _videoResolution = kHVideoResolution;
    _chat = [[VHallChat alloc] init];
    _chatDataArray = [NSMutableArray arrayWithCapacity:0];
}

- (void)initViews
{
    //阻止iOS设备锁屏
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [self registerLiveNotification];
    _hud = [[MBProgressHUD alloc]initWithView:self.view];
    [self.view addSubview:_hud];
    [_hud hide:YES];
    
    _chatMsgSend.layer.masksToBounds = YES;
    _chatMsgSend.layer.cornerRadius = 15;
    _chatMsgSend.layer.borderWidth  = 1;
    _chatMsgSend.layer.borderColor  = MakeColorRGBA(0xffffff, 0.5).CGColor;
    
    _msgTextField.layer.masksToBounds = YES;
    _msgTextField.layer.cornerRadius = 15;
    [_msgTextField setValue:[UIColor lightGrayColor] forKeyPath:@"_placeholderLabel.textColor"];

    // chat在播放之前初始化并设置代理
    _chat.delegate = self;
    [self filterSettingBtnClick:_defaultFilterSelectBtn];
    // TODO:暂时不支持此功能，但保留。
    _audioStartAndStopBtn.hidden = YES;
    
#if VHallFilterSDK_ENABLE
    _filterBtn.hidden = NO;
#else
    _filterBtn.hidden = YES;
#endif
}

- (void)viewDidLayoutSubviews
{
    __weak __typeof(self) weakself = self;
    if(!_chatView)
    {
        _chatView = [[VHLiveChatView alloc] initWithFrame:CGRectMake(10, 0,_chatContainerView.width-10,_chatContainerView.height - 50) msgTotal:^NSInteger{
            return  weakself.chatDataArray.count;
        } msgSource:^VHActMsg *(NSInteger index) {
            return  weakself.chatDataArray[index];
        }action:nil];
    }
    else
        _chatView.frame = CGRectMake(10, 0,_chatContainerView.width-10,_chatContainerView.height - 50);
    [_chatContainerView addSubview:_chatView];
}

- (void)initCameraEngine
{
    DeviceOrgiation deviceOrgiation;
    if (self.interfaceOrientation == UIInterfaceOrientationPortrait)
    {
        deviceOrgiation = kDevicePortrait;
    }else{
        deviceOrgiation = kDeviceLandSpaceRight;
    }
#if VHallFilterSDK_ENABLE
    self.engine = [[VHallLivePublishFilter alloc] initWithOrgiation:deviceOrgiation];
    BOOL ret = [_engine initCaptureVideo:AVCaptureDevicePositionFront];
    _torchBtn.hidden = YES;
    _isFontVideo = YES;
#else
    self.engine = [[VHallLivePublish alloc] initWithOrgiation:deviceOrgiation];
    BOOL ret = [_engine initCaptureVideo:AVCaptureDevicePositionBack];
#endif
    if (!ret) {
        VHLog(@"initCaptureVideo 调用失败！");
    }
    //音频初始化
    [_engine initAudio];
    
    self.engine.displayView.frame = _perView.bounds;
    self.engine.publishConnectTimes = 2;
    self.engine.videoCaptureFPS = (int)_videoCaptureFPS;
    self.engine.delegate = self;
    [self.perView insertSubview:_engine.displayView atIndex:0];
    _engine.videoResolution = _videoResolution;
    //开始视频采集
    [_engine startVideoCapture];
    
#if VHallFilterSDK_ENABLE
    _engine.openFilter = YES;
    [_engine setBeautifyFilterWithBilateral:10.0f Brightness:1.0f Saturation:1.0f];
#endif
}

#pragma mark - Lifecycle(ObserveValueForKeyPath)
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:kViewFramePath])
    {
        CGRect frame = [[change objectForKey:NSKeyValueChangeNewKey]CGRectValue];
        self.engine.displayView.frame = frame;
        if(self.interfaceOrientation == UIInterfaceOrientationPortrait)
        {
            if(_messageToolView==nil && frame.size.width <frame.size.height)
            {
                _messageToolView = [[VHMessageToolView alloc] initWithFrame:CGRectMake(0, frame.size.height - [VHMessageToolView defaultHeight], frame.size.width, [VHMessageToolView defaultHeight]) type:3];
                
                _messageToolView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
                _messageToolView.delegate = self;
                _messageToolView.hidden = YES;
                [self.view addSubview:_messageToolView];
            }
        }
        else if(frame.size.width >frame.size.height)
        {
            if(_messageToolView==nil)
            {
                _messageToolView = [[VHMessageToolView alloc] initWithFrame:CGRectMake(0, frame.size.height - [VHMessageToolView defaultHeight], frame.size.width, [VHMessageToolView defaultHeight]) type:3];
                
                _messageToolView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
                _messageToolView.delegate = self;
                _messageToolView.hidden = YES;
                [self.view addSubview:_messageToolView];
            }
        }
    }
}

#pragma mark -
#pragma mark - Camera

- (IBAction)swapBtnClick:(id)sender
{
    UIButton *btn=(UIButton*)sender;
    btn.enabled=NO;
    _isFontVideo = !_isFontVideo;
    
    if (_isFontVideo)
    {
      BOOL success=  [_engine swapCameras:AVCaptureDevicePositionFront];
        if(success)
        {
             _torchBtn.hidden = YES;
            //禁止快速切换摄像头
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                btn.enabled=YES;
               
            });
        }
    }else{
       BOOL success=  [_engine swapCameras:AVCaptureDevicePositionBack];
        if (success)
        {
            _torchBtn.hidden = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                btn.enabled=YES;
                
            });
        }
    }
}

- (IBAction)torchBtnClick:(UIButton*)sender
{
    _torchType = !_torchType;
    sender.selected = _torchType;
    if (_torchType) {
        [_engine setDeviceTorchModel:AVCaptureTorchModeOn];
    }else{
        [_engine setDeviceTorchModel:AVCaptureTorchModeOff];
    }
}

- (IBAction)onlyVideoBtnClick:(UIButton*)sender
{
    _onlyVideo = !_onlyVideo;
    sender.selected = _onlyVideo;
    if (_onlyVideo)
    {
        //[_engine pauseAudioCapture];
        _engine.isMute = YES;
//        [UIAlertView popupAlertByDelegate:nil title:@"开始静音" message:nil cancel:@"知道了" others:nil];
    }
    else
    {
        _engine.isMute = NO;
        //[_engine pauseAudioCapture];
//        [UIAlertView popupAlertByDelegate:nil title:@"结束静音" message:nil cancel:@"知道了" others:nil];
    }
}

- (IBAction)startVideoPlayer
{
#if (TARGET_IPHONE_SIMULATOR)
    [self showMsg:@"无法在模拟器上发起直播！" afterDelay:1.5];
    return;
#endif
    
    if (!_isVideoStart)
    {
        //        _isAudioStart = YES;
        //        [self startAudioPlayer];
        //    self.engine.audioBitRate = _audioBitRate;
#if VHallFilterSDK_ENABLE
        _engine.videoBitRate = 1200 * 1000;
#else
        _engine.videoBitRate = _videoBitRate;
#endif
        _engine.audioBitRate = _audioBitRate;
        [_chatDataArray removeAllObjects];
        [_chatView update];
        [_hud show:YES];
        NSMutableDictionary * param = [[NSMutableDictionary alloc]init];
        param[@"id"] =  _roomId;
        param[@"access_token"] = _token;
        param[@"is_single_audio"] = @"0";    // 0 ：视频， 1：音频
        [_engine startLive:param];
    }else{
        _isVideoStart=NO;
        _bitRateLabel.text = @"";
        [_hud hide:YES];
        _videoStartAndStopBtn.selected = NO;
        [self chatShow:NO];
        [_engine stopLive];//停止活动
       
    }
    _logView.hidden = YES;
    //_isVideoStart = !_isVideoStart;
}

- (IBAction)startAudioPlayer
{
    //    TODO:暂时不支持此功能，但保留。
    //    if (!_isAudioStart)
    //    {
    //        _isVideoStart = YES;
    //        [self startVideoPlayer];
    //
    //        _logView.hidden = NO;
    //        _chatBtn.hidden = NO;
    //        [_hud show:YES];

    //        NSMutableDictionary * param = [[NSMutableDictionary alloc]init];
    //        param[@"id"] =  _roomId;
    //        param[@"access_token"] = _token;
    //        param[@"is_single_audio"] = @"1";   // 0 ：视频， 1：音频
    //        [_engine startLive:param];
    //    }else{
    //        _logView.hidden = YES;
    //        _bitRateLabel.text = @"";
    //        _chatBtn.hidden = YES;
    //        [_hud hide:YES];
    //        [_audioStartAndStopBtn setTitle:@"音频直播" forState:UIControlStateNormal];
    //        [_engine disconnect];//停止向服务器推流
    //    }
    //    _isAudioStart = !_isAudioStart;
}

#pragma mark - Camera(CameraEngineDelegate)

-(void)firstCaptureImage:(UIImage *)image
{
    VHLog(@"第一张图片");
}

-(void)publishStatus:(LiveStatus)liveStatus withInfo:(NSDictionary *)info
{
    void (^resetStartPlay)(NSString * msg) = ^(NSString * msg){
        _isVideoStart = NO;
        _bitRateLabel.text = @"";
        _videoStartAndStopBtn.selected = NO;
        [self chatShow:NO];
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIAlertView popupAlertByDelegate:nil title:msg message:nil];
        });
    };

    [_hud hide:YES];
    
    BOOL errorLiveStatus = NO;
    NSString * content = info[@"content"];
    switch (liveStatus)
    {
        case kLiveStatusUploadSpeed:
        {
            _bitRateLabel.text = [NSString stringWithFormat:@"%@ kb/s",content];
        }
            break;
        case kLiveStatusPushConnectSucceed:
        {
            [self chatShow:YES];
            _isVideoStart=YES;
            if (_isVideoStart || _isAudioStart) {
                _videoStartAndStopBtn.selected = YES;
            }
        }
            break;
        case kLiveStatusSendError:
        {
            resetStartPlay(@"网断啦！不能再带你直播带你飞了");
            errorLiveStatus = YES;
        }
            break;
        case kLiveStatusPushConnectError:
        {
            resetStartPlay(@"服务器任性...连接失败");
            errorLiveStatus = YES;
        }
            break;
        case kLiveStatusParamError:
        {
            resetStartPlay(@"参数错误");
            errorLiveStatus = YES;
        }
            break;
        case kLiveStatusGetUrlError:
        {
            _isVideoStart=NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMsg:content afterDelay:1.5];
            });
            errorLiveStatus = YES;
        }
            break;
        case kLiveStatusUploadNetworkOK:
        {
            _bitRateLabel.textColor = [UIColor greenColor];
            VHLog(@"kLiveStatusNetworkStatus:%@",content);
        }
            break;
        case kLiveStatusUploadNetworkException:
        {
            _bitRateLabel.textColor = [UIColor redColor];
            VHLog(@"kLiveStatusNetworkStatus:%@",content);
            errorLiveStatus = YES;
        }
            break;
        case kLiveStatusRecvStreamType:
        {
            
        }
            break;
        default:
            break;
    }
}

#pragma mark -
#pragma mark - Filter

- (IBAction)filterBtnClick:(UIButton *)sender
{
//    [_chatMsgInput resignFirstResponder];
    _filterBtn.selected = !_filterBtn.selected;
    if(_filterBtn.selected)
    {
        _hideKeyBtn.hidden = NO;
        _filterView.alpha = 0.0f;
        [UIView animateWithDuration:0.3f animations:^{
            _filterView.alpha = 1.0f;
        }];
    }
    else
    {
        _hideKeyBtn.hidden = YES;
        _filterView.alpha = 1.0f;
        [UIView animateWithDuration:0.3f animations:^{
            _filterView.alpha = 0.0f;
        }];
    }
}

- (IBAction)filterSettingBtnClick:(UIButton *)sender
{
    if (sender.selected) {
        return;
    }
    
    if (_lastFilterSelectBtn) {
        [_lastFilterSelectBtn setBackgroundColor:MakeColorRGBA(0x000000,0.5)];
        _lastFilterSelectBtn.selected = NO;
    }
    
    sender.selected = YES;
    [sender setBackgroundColor:MakeColorRGBA(0xfd3232,0.5)];
    _lastFilterSelectBtn = sender;
    
#if VHallFilterSDK_ENABLE
    switch (sender.tag) {
        case 1:
            _engine.openFilter = YES;
            [_engine setBeautifyFilterWithBilateral:10.0f Brightness:1.0f Saturation:1.0f];
            break;
        case 2:
            _engine.openFilter = YES;
            [_engine setBeautifyFilterWithBilateral:8.0f Brightness:1.05f Saturation:1.0f];
            break;
        case 3:
            _engine.openFilter = YES;
            [_engine setBeautifyFilterWithBilateral:6.0f Brightness:1.10f Saturation:1.0f];
            break;
        case 4:
            _engine.openFilter = YES;
            [_engine setBeautifyFilterWithBilateral:4.0f Brightness:1.15f Saturation:1.0f];
            break;
        case 5:
            _engine.openFilter = YES;
            [_engine setBeautifyFilterWithBilateral:2.0f Brightness:1.20f Saturation:1.0f];
            break;
        default:
        case 0:
            _engine.openFilter = NO;
            break;
    }
#endif
}

#pragma mark - Filter(LivePublishFilterDelegate)
#if VHallFilterSDK_ENABLE
- (void)addGPUImageFilter:(GPUImageVideoCamera *)source Output:(GPUImageView *)output
{
//    GPUImageiOSBlurFilter *filter = [[GPUImageiOSBlurFilter alloc] init];
//    filter.saturation = 2.0f;
//    [source addTarget:filter];
//    [filter addTarget:output];
}
#endif

#pragma mark -
#pragma mark - Chat && QA

- (void)chatShow:(BOOL)isShow
{
    if(isShow)
    {
        _chatContainerView.alpha = 0.0f;
        [UIView animateWithDuration:0.3f animations:^{
            _chatContainerView.alpha = 1.0f;
        }];
        _closeBtn.hidden = YES;
        _infoView.hidden = NO;
        [self showTimeInfo];
    }
    else
    {
        _chatContainerView.alpha = 1.0f;
        [UIView animateWithDuration:0.3f animations:^{
            _chatContainerView.alpha = 0.0f;
        }];
        _closeBtn.hidden = NO;
        _infoView.hidden = YES;
        if(_timer)
        {
            dispatch_source_cancel(_timer);
            _timer = nil;
        }
        _bitRateLabel.text = @"0 kb/s";
        _bitRateLabel.textColor = [UIColor greenColor];
        _timeLabel.text    = @"00:00:00";
    }
}

- (IBAction)sendMsgButtonClick:(UIButton *)sender {
    _messageToolView.hidden = NO;
    _messageToolView.msgTextView.hidden = NO;
    [_messageToolView.msgTextView becomeFirstResponder];
    [self.view addSubview:_messageToolView];
    _hideKeyBtn.hidden = NO;
}

#pragma mark - Chat && QA(VHallChatDelegate)
- (void)reciveOnlineMsg:(NSArray *)msgs
{
    if (msgs.count > 0) {
        for (VHallOnlineStateModel *m in msgs) {
            VHActMsg * msg = [[VHActMsg alloc]initWithMsgType:ActMsgTypeMsg];
            msg.actId= m.room;
            msg.joinId= m.join_id;
            msg.formUserIcon= m.avatar;
            msg.formUserName= m.user_name;
            msg.formUserId= m.account_id;
            msg.time= m.time;

            NSString *event;
            NSString *role;
            if([m.event isEqualToString:@"online"]) {
                event = @"进入";
            }else if([m.event isEqualToString:@"offline"]){
                event = @"离开";
            }
            
            if([m.role isEqualToString:@"host"]) {
                role = @"主持人";
            }else if([m.role isEqualToString:@"guest"]) {
                role = @"嘉宾";
            }else if([m.role isEqualToString:@"assistant"]) {
                role = @"助手";
            }else if([m.role isEqualToString:@"user"]) {
                role = @"观众";
            }
            
            msg.text = [NSString stringWithFormat:@"%@\n[%@] %@房间:%@ 在线人数:%@ 参会人数:%@",m.time,role,event,m.room, m.concurrent_user, m.attend_count];
            [_chatDataArray addObject:msg];
        }
        [_chatView update];
    }
}

- (void)reciveChatMsg:(NSArray *)msgs
{
    if (msgs.count > 0) {
        for (VHallChatModel *m in msgs) {
            VHActMsg * msg = [[VHActMsg alloc]initWithMsgType:ActMsgTypeMsg];
            msg.actId= m.room;
            msg.joinId= m.join_id;
            msg.formUserIcon= m.avatar;
            msg.formUserName= m.user_name;
            msg.formUserId= m.account_id;
            msg.time= m.time;
            msg.text = [NSString stringWithFormat:@"%@\n%@",m.time, m.text];
            [_chatDataArray addObject:msg];
        }
        [_chatView update];
    }
}


-(void)showTimeInfo{
    if(_timer)
    {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
    _liveTime = 0;
    dispatch_queue_t queue = dispatch_queue_create("my queue", 0);
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), 1 * NSEC_PER_SEC, 0);//间隔1秒
    dispatch_source_set_event_handler(_timer, ^(){
        _liveTime++;
        NSString *strInfo = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",_liveTime/3600,(_liveTime/60)%60,_liveTime%60];
        dispatch_async(dispatch_get_main_queue(), ^{
            if(_timeLabel)
            {
                _timeLabel.text = strInfo;
            }
        });
    });
    dispatch_resume(_timer);
}

- (IBAction)hideKey:(id)sender {
    [_messageToolView endEditing:YES];
 
    _hideKeyBtn.hidden = YES;
    _filterBtn.selected = NO;
    [UIView animateWithDuration:0.3f animations:^{
        _filterView.alpha = 0.0f;
    }];
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 0.2);
    dispatch_after(time, dispatch_get_main_queue(), ^{
        _messageToolView.hidden = YES;
        _messageToolView.msgTextView.hidden = YES;
        [_messageToolView removeFromSuperview];
    });
}

#pragma mark messageToolViewDelegate
- (void)didSendText:(NSString *)text
{
    if(text == nil || text.length <= 0)
    {
        [super showMsg:@"发送内容不能为空" afterDelay:1.5];
        return;
    }
    
    [self hideKey:nil];
    [_chat sendMsg:text success:^{
    } failed:^(NSDictionary *failedData) {
        NSString* error = [NSString stringWithFormat:@"(%@)%@", failedData[@"code"],failedData[@"content"]];
        [super showMsg:error afterDelay:2];
    }];
}
- (void)cancelTextView
{
    [self hideKey:nil];
}

@end
