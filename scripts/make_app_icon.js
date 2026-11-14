// Run on macOS: osascript -l JavaScript scripts/make_app_icon.js <repository-path>
ObjC.import('Foundation');
ObjC.import('CoreGraphics');
ObjC.import('ImageIO');
function run(args) {
    var root = args[0];
    var sourceURL = $.NSURL.fileURLWithPath(root + '/Design/AppIconSource.png');
    var source = $.CGImageSourceCreateWithURL(sourceURL, null);
    var image = $.CGImageSourceCreateImageAtIndex(source, 0, null);
    var space = $.CGColorSpaceCreateDeviceRGB();
    var context = $.CGBitmapContextCreate(null, 1024, 1024, 8, 4096, space, $.kCGImageAlphaNoneSkipLast);
    var rect = $.CGRectMake(0, 0, 1024, 1024);
    $.CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    $.CGContextFillRect(context, rect);
    $.CGContextSetInterpolationQuality(context, $.kCGInterpolationHigh);
    $.CGContextDrawImage(context, rect, image);
    var result = $.CGBitmapContextCreateImage(context);
    var destinationURL = $.NSURL.fileURLWithPath(root + '/MusicApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png');
    var destination = $.CGImageDestinationCreateWithURL(destinationURL, $('public.png'), 1, null);
    $.CGImageDestinationAddImage(destination, result, null);
    if (!$.CGImageDestinationFinalize(destination)) { throw new Error('Cannot write app icon'); }
}
