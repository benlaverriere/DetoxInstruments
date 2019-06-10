//
//  DTXSamplePlotController.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 01/06/2017.
//  Copyright © 2017-2019 Wix. All rights reserved.
//

#import "DTXSamplePlotController-Private.h"
#import "DTXGraphHostingView.h"
#import "DTXInstrumentsModel.h"
#import "NSFormatter+PlotFormatters.h"
#import <LNInterpolation/LNInterpolation.h>
#import "DTXDetailController.h"
#import "NSAppearance+UIAdditions.h"
#import "DTXRecording+UIExtensions.h"
#import "DTXScatterPlotView.h"
#import "DTXSeparatorView.h"

NSString* const DTXPlotControllerRequiredHeightDidChangeNotification = @"DTXPlotControllerRequiredHeightDidChangeNotification";

@interface DTXSamplePlotController () <CPTScatterPlotDelegate>

@end

@implementation DTXSamplePlotController
{
	DTXPlotRange* _pendingGlobalPlotRange;
	DTXPlotRange* _pendingPlotRange;
	DTXPlotRange* _pendingDataLimitRange;
	
	NSStoryboard* _scene;
	
	NSArray<DTXPlotViewTextAnnotation*>* _textAnnotations;
	
	NSArray* _cachedPlotColors;
	NSArray* _cachedAdditionalPlotColors;
	
	NSMenu* _cachedGroupingMenu;
}

@synthesize delegate = _delegate;
@synthesize document = _document;
@synthesize sampleClickDelegate = _sampleClickDelegate;
@synthesize parentPlotController = _parentPlotController;
@dynamic helpTopicName;

+ (Class)graphHostingViewClass
{
	return [DTXGraphHostingView class];
}

+ (Class)UIDataProviderClass
{
	return nil;
}

- (instancetype)initWithDocument:(DTXRecordingDocument*)document isForTouchBar:(BOOL)isForTouchBar
{
	self = [super initForTouchBar:isForTouchBar];

	if(self)
	{
		_document = document;
		_scene = [NSStoryboard storyboardWithName:@"Profiler" bundle:nil];
		
		[self plotViews];
	}
	
	return self;
}

- (NSArray<DTXDetailController*>*)dataProviderControllers
{
	DTXDetailController* detailController = [_scene instantiateControllerWithIdentifier:@"DTXOutlineDetailController"];
	detailController.detailDataProvider = [[self.class.UIDataProviderClass alloc] initWithDocument:_document plotController:self];
	
	return @[detailController];
}

- (void)mouseEntered:(NSEvent *)event
{
	
}

- (void)mouseExited:(NSEvent *)event
{
	[self _updateTextAnnotations:nil];
}

- (void)mouseMoved:(NSEvent *)event
{
	NSPoint pointInView = [self.wrapperView convertPoint:[event locationInWindow] fromView:nil];

	NSMutableArray<NSDictionary*>* dataPoints = [NSMutableArray new];

	for(__kindof DTXPlotView* plotView in self.plotViews)
	{
		if([plotView isKindOfClass:DTXScatterPlotView.class])
		{
			DTXScatterPlotView* scatterPlotView = plotView;

			double position;
			NSUInteger pointIdx = [scatterPlotView indexOfPointAtViewPosition:pointInView.x positionInPlot:&position valueAtPlotPosition:NULL];
			
			if(pointIdx == NSNotFound)
			{
				return;
			}
			
			double value = [scatterPlotView valueOfPointIndex:pointIdx];

			NSMutableDictionary* dataPoint = @{@"position": @(position), @"value": [self.class.formatterForDataPresentation stringForObjectValue:[self transformedValueForFormatter:@(value)]]}.mutableCopy;
			if(scatterPlotView.hasAdditionalPoints)
			{
				double additionalValue = [scatterPlotView additionalValueOfPointIndex:pointIdx];
				dataPoint[@"additionalValue"] = [self.class.additionalFormatterForDataPresentation stringForObjectValue:[self transformedValueForFormatter:@(additionalValue)]];
			}
			
			[dataPoints addObject:dataPoint];
		}
	}

	if(dataPoints.count != self.plotViews.count)
	{
		return;
	}

	NSMutableArray* textAnnotations = [NSMutableArray new];

	[dataPoints enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull presentable, NSUInteger idx, BOOL * _Nonnull stop) {
		DTXPlotViewTextAnnotation* textAnnotation = [DTXPlotViewTextAnnotation new];
		textAnnotation.position = [presentable[@"position"] doubleValue];
		textAnnotation.text = presentable[@"value"];
		textAnnotation.additionalText = presentable[@"additionalValue"];
		textAnnotation.priority = 1000;

		[self _updateAnnotationColors:@[textAnnotation] forPlotIndex:idx];

		[textAnnotations addObject:textAnnotation];
	}];

	[self _updateTextAnnotations:textAnnotations];
}

- (void)_updateTextAnnotations:(NSArray*)newTextAnnotations
{
	[_textAnnotations enumerateObjectsUsingBlock:^(DTXPlotViewTextAnnotation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		DTXPlotView* plotView = self.plotViews[idx];
		NSMutableArray* newAnnotations = plotView.annotations.mutableCopy ?: [NSMutableArray new];
		[newAnnotations removeObject:obj];
		if(newTextAnnotations)
		{
			[newAnnotations addObject:newTextAnnotations[idx]];
		}
		
		plotView.annotations = newAnnotations;
	}];
	
	_textAnnotations = newTextAnnotations;
}

- (void)updateLayerHandler
{
	[self.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[self _updateAnnotationColors:obj.annotations forPlotIndex:idx];
		obj.annotations = obj.annotations;
	}];
}

- (BOOL)usesInternalPlots
{
	return YES;
}

- (void)setupPlotViews
{
	NSArray<__kindof DTXPlotView*>* plotViews = self.plotViews;
	
	DTXPlotRange *globalRange;
	if(_pendingGlobalPlotRange)
	{
		globalRange = _pendingGlobalPlotRange;
		_pendingGlobalPlotRange = nil;
	}
	else
	{
		globalRange = [DTXPlotRange plotRangeWithPosition:0 length:[_document.lastRecording.defactoEndTimestamp timeIntervalSinceReferenceDate] - [_document.firstRecording.defactoStartTimestamp timeIntervalSinceReferenceDate]];
	}
	
	DTXPlotRange* range = globalRange;
	if(_pendingPlotRange)
	{
		range = _pendingPlotRange;
		_pendingPlotRange = nil;
	}
	
	DTXPlotRange* dataLimitRange = globalRange;
	if(_pendingDataLimitRange)
	{
		dataLimitRange = _pendingDataLimitRange;
		_pendingDataLimitRange = nil;
	}
	
	double requiredMinHeight = self.isForTouchBar ? DTXCurrentTouchBarHeight() : 80 / plotViews.count;
	
	NSUInteger plotViewIdx = 0;
	for (__kindof DTXPlotView* plotView in plotViews)
	{
		plotView.globalPlotRange = globalRange;
		plotView.plotRange = range;
		plotView.dataLimitRange = dataLimitRange;
		plotView.delegate = self;
		plotView.minimumHeight = requiredMinHeight;
		
		plotView.plotIndex = plotViewIdx;
		plotViewIdx++;
		
		[self.plotStackView addArrangedSubview:plotView];
		
		if(self.includeSeparatorsInStackView && plotViewIdx < plotViews.count)
		{
			NSView* box = [DTXSeparatorView new];
			box.translatesAutoresizingMaskIntoConstraints = NO;
			[NSLayoutConstraint activateConstraints:@[
													  [box.heightAnchor constraintEqualToConstant:1],
													  ]];
			
			[self.plotStackView addArrangedSubview:box];
		}
	}
	plotViews.lastObject.insets = self.rangeInsets;
}

- (void)reloadPlotViews
{
	[self _removeHighlightNotifyingDelegate:YES];
	
	[self.plotStackView.arrangedSubviews.copy enumerateObjectsUsingBlock:^(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[obj removeFromSuperviewWithoutNeedingDisplay];
	}];
	
	[self setupPlotViews];
}

- (void)didFinishViewSetup
{
	[super didFinishViewSetup];
	
	[self prepareSamples];
	
	NSTrackingArea* tracker = [[NSTrackingArea alloc] initWithRect:self.wrapperView.bounds options:NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved owner:self userInfo:nil];
	[self.wrapperView addTrackingArea:tracker];
	
	__weak auto weakSelf = self;
	self.wrapperView.updateLayerHandler = ^ (NSView* view) {
		[weakSelf updateLayerHandler];
		
		[weakSelf.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			[obj reloadData];
		}];
	};
}

- (void)setGlobalPlotRange:(DTXPlotRange*)globalPlotRange
{	
	if(self.graph != nil)
	{
		[(CPTXYPlotSpace *)self.graph.defaultPlotSpace setGlobalXRange:globalPlotRange.cptPlotRange];
	}
	else if(self.plotStackView.arrangedSubviews.count > 0)
	{
		for (DTXPlotView* plotView in self.plotViews) {
			plotView.globalPlotRange = globalPlotRange;
		}
	}
	else
	{
		_pendingGlobalPlotRange = globalPlotRange;
	}
}

- (void)setPlotRange:(DTXPlotRange *)plotRange
{
	if(self.graph != nil)
	{
		[(CPTXYPlotSpace *)self.graph.defaultPlotSpace setXRange:plotRange.cptPlotRange];
	}
	else if(self.plotStackView.arrangedSubviews.count > 0)
	{
		for (DTXPlotView* plotView in self.plotViews) {
			plotView.plotRange = plotRange;
		}
	}
	else
	{
		_pendingPlotRange = plotRange;
	}
}

- (void)setDataLimitRange:(DTXPlotRange*)plotRange;
{
	if(self.plotStackView.arrangedSubviews.count > 0)
	{
		for (DTXPlotView* plotView in self.plotViews) {
			plotView.dataLimitRange = plotRange;
		}
	}
	else
	{
		_pendingDataLimitRange = plotRange;
	}
}

- (void)_zoomToScale:(CGFloat)scale
{
	CGPoint pt;
	
	if(self.wrapperView.window.currentEvent.type == NSEventTypeKeyDown || self.wrapperView.window.currentEvent.type == NSEventTypeKeyUp)
	{
		pt = [self.plotViews.firstObject convertPointFromWindow:self.wrapperView.window.mouseLocationOutsideOfEventStream];
	}
	else
	{
		pt = CGPointMake(CGRectGetMidX(self.wrapperView.bounds), CGRectGetMidY(self.wrapperView.bounds));
	}
	
	[self.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[obj scalePlotRange:scale atPoint:pt];
	}];
}

- (void)zoomIn
{
	[self _zoomToScale:2.0];
}

- (void)zoomOut
{
	[self _zoomToScale:0.5];
}

- (void)zoomToFitAllData
{
	[self.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[obj scalePlotRange:obj.plotRange.length / obj.globalPlotRange.length atPoint:NSZeroPoint];
	}];
}

- (DTXPlotRange*)plotRangeForSample:(DTXSample*) sample
{
	return [DTXPlotRange plotRangeWithPosition:sample.timestamp.timeIntervalSinceReferenceDate - self.document.firstRecording.defactoStartTimestamp.timeIntervalSinceReferenceDate length:0];
}

- (void)highlightSample:(DTXSample*)sample
{
	DTXPlotRange* range = [self plotRangeForSample:sample];
	
	[self.delegate plotController:self didHighlightRange:range];
	
	[self _highlightRange:range sampleIndex:NSNotFound isShadow:NO plotIndex:NSNotFound valueAtClickPosition:0 nofityDelegate:NO];
}

- (void)_highlightSample:(DTXSample*)sample sampleIndex:(NSUInteger)sampleIdx plotIndex:(NSUInteger)plotIndex positionInPlot:(double)position valueAtClickPosition:(double)value
{
	DTXPlotRange* range = [DTXPlotRange plotRangeWithPosition:position length:0];
	
	[self.delegate plotController:self didHighlightRange:range];
	
	[self _highlightRange:range sampleIndex:sampleIdx isShadow:NO plotIndex:plotIndex valueAtClickPosition:value nofityDelegate:NO];
}

- (void)shadowHighlightRange:(DTXPlotRange*)range
{
	[self _highlightRange:range sampleIndex:NSNotFound isShadow:YES plotIndex:NSNotFound valueAtClickPosition:0 nofityDelegate:NO];
}

- (void)_highlightRange:(DTXPlotRange*)range sampleIndex:(NSUInteger)sampleIdx isShadow:(BOOL)isShadow plotIndex:(NSUInteger)plotIndex valueAtClickPosition:(double)value nofityDelegate:(BOOL)notifyDelegate
{
	[self _removeHighlightNotifyingDelegate:NO];
	
	[self.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		NSMutableArray* annotations = [NSMutableArray new];
		if(range.length > 0)
		{
			DTXPlotViewRangeAnnotation* annotation1 = [DTXPlotViewRangeAnnotation new];
			annotation1.position = 0;
			annotation1.end = range.position;
			annotation1.opacity = 0.0;
			
			DTXPlotViewRangeAnnotation* annotation2 = [DTXPlotViewRangeAnnotation new];
			annotation2.position = range.position + range.length;
			annotation2.end = DBL_MAX;
			annotation2.opacity = 0.0;
			
			[annotations addObject:annotation1];
			[annotations addObject:annotation2];
			
			DTXPlotViewLineAnnotation* annotation3 = [DTXPlotViewLineAnnotation new];
			annotation3.position = range.position;
			if(self.isForTouchBar == NO)
			{
				annotation3.opacity = 0.4;
			}
			
			DTXPlotViewLineAnnotation* annotation4 = [DTXPlotViewLineAnnotation new];
			annotation4.position = range.position + range.length;
			if(self.isForTouchBar == NO)
			{
				annotation4.opacity = 0.4;
			}
			
			[annotations addObject:annotation3];
			[annotations addObject:annotation4];
		}
		else
		{
			DTXPlotViewLineAnnotation* annotation1 = [DTXPlotViewLineAnnotation new];
			annotation1.position = range.position;
			if(self.isForTouchBar == NO)
			{
				annotation1.opacity = self.wrapperView.effectiveAppearance.isDarkAppearance ? 1.0 : isShadow ? 0.4 : 1.0;
			}
			
			if([obj isKindOfClass:DTXScatterPlotView.class])
			{
				DTXScatterPlotView* scatterPlotView = (id)obj;
				if(isShadow == NO || self.isForTouchBar == YES)
				{
					double textValue;
					if(sampleIdx != NSNotFound)
					{
						textValue = [scatterPlotView valueOfPointIndex:sampleIdx];
					}
					else
					{
						if(idx == plotIndex)
						{
							textValue = value;
						}
						else
						{
							textValue = [scatterPlotView valueAtPlotPosition:range.position exact:YES];
						}
					}
					
					DTXPlotViewTextAnnotation* text = [DTXPlotViewTextAnnotation new];
					text.text = [self.class.formatterForDataPresentation stringForObjectValue:[self transformedValueForFormatter:@(textValue)]];
					
					if(scatterPlotView.hasAdditionalPoints)
					{
						double additionalTextValue;
						if(sampleIdx != NSNotFound)
						{
							additionalTextValue = [scatterPlotView additionalValueOfPointIndex:sampleIdx];
						}
						else
						{
							if(idx == plotIndex)
							{
								additionalTextValue = value;
							}
							else
							{
								additionalTextValue = [scatterPlotView additionalValueAtPlotPosition:range.position exact:YES];
							}
						}
						
						text.additionalText = [self.class.additionalFormatterForDataPresentation stringForObjectValue:[self transformedValueForFormatter:@(additionalTextValue)]];
					}
					
					text.position = annotation1.position;
					[annotations addObject:text];
				}
			}
			
			[annotations addObject:annotation1];
		}
		
		if(_textAnnotations != nil)
		{
			[annotations addObject:_textAnnotations[idx]];
		}
		
		[self _updateAnnotationColors:annotations forPlotIndex:idx];
		
		obj.annotations = annotations;
	}];
	
	if(notifyDelegate)
	{
		[self.delegate plotController:self didHighlightRange:range];
	}
}

- (void)removeHighlight
{
	[self _removeHighlightNotifyingDelegate:YES];
}

- (void)_removeHighlightNotifyingDelegate:(BOOL)notify;
{
	[self.plotViews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if(_textAnnotations != nil)
		{
			obj.annotations = @[_textAnnotations[idx]];
		}
		else
		{
			obj.annotations = nil;
		}
	}];
	
	if(notify)
	{
		[self.delegate plotControllerDidRemoveHighlight:self];
	}
}

- (NSArray<NSColor*>*)_cachedPlotColors
{
	if(_cachedPlotColors == nil)
	{
		_cachedPlotColors = self.plotColors;
	}
	
	return _cachedPlotColors;
}

- (NSArray<NSColor*>*)_cachedAdditionalPlotColors
{
	if(_cachedAdditionalPlotColors == nil)
	{
		_cachedAdditionalPlotColors = self.additionalPlotColors;
	}
	
	return _cachedAdditionalPlotColors;
}

- (NSColor*)_plotColorForIdx:(NSUInteger)idx
{
	if(idx >= self._cachedPlotColors.count)
	{
		return self._cachedPlotColors.lastObject;
	}
	
	return self._cachedPlotColors[idx];
}

- (NSColor*)_additionalPlotColorForIdx:(NSUInteger)idx
{
	if(idx >= self._cachedAdditionalPlotColors.count)
	{
		return self._cachedAdditionalPlotColors.lastObject;
	}
	
	return self._cachedAdditionalPlotColors[idx];
}

- (void)_updateAnnotationColors:(NSArray<DTXPlotViewAnnotation*>*)annotations forPlotIndex:(NSUInteger)plotIdx
{
	BOOL isDark = self.wrapperView.effectiveAppearance.isDarkAppearance;
	
	[annotations enumerateObjectsUsingBlock:^(DTXPlotViewAnnotation * _Nonnull annotation, NSUInteger idx, BOOL * _Nonnull stop) {
		if([annotation isKindOfClass:DTXPlotViewLineAnnotation.class])
		{
			DTXPlotViewLineAnnotation* line = (id)annotation;
			
			if(self.wrapperView.effectiveAppearance.isDarkAppearance)
			{
				line.color = NSColor.whiteColor;
			}
			else
			{
				line.color =  [[self _plotColorForIdx:plotIdx] deeperColorWithAppearance:self.wrapperView.effectiveAppearance modifier:0.3];
			}
		}
		else if([annotation isKindOfClass:DTXPlotViewTextAnnotation.class])
		{
			DTXPlotViewTextAnnotation* text = (id)annotation;
			
			if(isDark)
			{
				text.color = NSColor.textColor;
				text.textBackgroundColor = [[self _plotColorForIdx:plotIdx] shallowerColorWithAppearance:self.wrapperView.effectiveAppearance modifier:0.15];
				text.additionalTextColor = [[self _additionalPlotColorForIdx:plotIdx] deeperColorWithAppearance:self.wrapperView.effectiveAppearance modifier:0.4];
			}
			else
			{
				text.color = [[self _plotColorForIdx:plotIdx] deeperColorWithAppearance:self.wrapperView.effectiveAppearance modifier:0.3];
				text.textBackgroundColor = NSColor.textBackgroundColor;
				text.additionalTextColor = [self _additionalPlotColorForIdx:plotIdx];
			}
			
			text.textColor = text.color;
			text.valueColor = [[self _plotColorForIdx:plotIdx] shallowerColorWithAppearance:self.wrapperView.effectiveAppearance modifier:0.15];
		}
	}];
}

- (void)noteOfSampleInsertions:(NSArray<NSNumber*>*)insertions updates:(NSArray<NSNumber*>*)updates forPlotAtIndex:(NSUInteger)index
{
}

- (NSString *)displayName
{
	return @"";
}

- (NSString *)toolTip
{
	return nil;
}

- (NSImage*)displayIcon
{
	return nil;
}

- (NSImage *)smallDisplayIcon
{
	NSImage* image = [NSImage imageNamed:[NSString stringWithFormat:@"%@_small", self.displayIcon.name]];
	image.size = NSMakeSize(16, 16);
	
	return image;
}

- (NSImage *)secondaryIcon
{
    return nil;
}

- (NSFont *)titleFont
{
	return [NSFont systemFontOfSize:NSFont.systemFontSize];
}

- (CGFloat)requiredHeight
{
	return 80;
}

- (void)prepareSamples
{
	
}

- (NSArray<DTXPlotView *> *)plotViews
{
	return nil;
}

- (BOOL)includeSeparatorsInStackView
{
	return NO;
}

- (NSArray<NSString*>*)propertiesToFetch;
{
	return @[@"timestamp"];
}

- (NSArray<NSString*>*)relationshipsToFetch
{
	return nil;
}

- (NSArray<NSColor*>*)plotColors
{
	return @[];
}

- (NSArray<NSColor*>*)additionalPlotColors;
{
	return nil;
}

- (NSArray<NSString *>*)plotTitles
{
	return @[];
}

- (NSArray<CPTPlotSpaceAnnotation*>*)graphAnnotationsForGraph:(CPTGraph*)graph
{
	return @[];
}

+ (NSFormatter*)formatterForDataPresentation
{
	return [NSFormatter dtx_stringFormatter];
}

+ (NSFormatter *)additionalFormatterForDataPresentation
{
	return [NSFormatter dtx_stringFormatter];
}

- (NSEdgeInsets)rangeInsets
{
	return NSEdgeInsetsMake(0, 0, 1, 0);
}

- (id)transformedValueForFormatter:(id)value
{
	return value;
}

- (BOOL)canReceiveFocus
{
	return self.isForTouchBar == NO;
}

- (NSArray<NSString *> *)legendTitles
{
	return self.plotTitles;
}

- (NSArray<NSColor *> *)legendColors
{
	return self._cachedPlotColors;
}

- (NSMenu *)groupingSettingsMenu
{
	return nil;
}

- (BOOL)supportsQuickSettings
{
	return NO;
}

#pragma mark Internal Plots

- (void)plotViewDidChangePlotRange:(DTXPlotView *)plotView
{
	[self.plotStackView.arrangedSubviews enumerateObjectsUsingBlock:^(__kindof DTXPlotView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if(plotView == obj)
		{
			return;
		}
		
		if([obj isKindOfClass:DTXPlotView.class] == NO)
		{
			return;
		}
		
		obj.plotRange = plotView.plotRange;
	}];
	
	[_delegate plotController:self didChangeToPlotRange:plotView.plotRange];
}

@end
