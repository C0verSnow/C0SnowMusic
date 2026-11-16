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
    var logoDirectory = root + '/MusicApp/Resources/Assets.xcassets/AppLogo.imageset';
    $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(logoDirectory, true, $(), $());
    var logoURL = $.NSURL.fileURLWithPath(logoDirectory + '/AppLogo.png');
    var logo = $.CGImageDestinationCreateWithURL(logoURL, $('public.png'), 1, null);
    $.CGImageDestinationAddImage(logo, result, null);
    if (!$.CGImageDestinationFinalize(logo)) { throw new Error('Cannot write placeholder logo'); }
    $(JSON.stringify({images: [{filename: 'AppLogo.png', idiom: 'universal'}], info: {author: 'xcode', version: 1}}, null, 2) + '\n')
        .writeToFileAtomicallyEncodingError(logoDirectory + '/Contents.json', true, $.NSUTF8StringEncoding, $());
}
