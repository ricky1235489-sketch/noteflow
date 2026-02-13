import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// OpenSheetMusicDisplay 渲染器 - 產生專業品質的樂譜
/// 類似 PopPianoAI 的渲染效果，支援播放游標
class OsmdSheetWidget extends StatefulWidget {
  final String musicXml;
  final String? title;
  final int? currentMeasure; // Current measure index for cursor
  final VoidCallback? onReady;

  const OsmdSheetWidget({
    super.key,
    required this.musicXml,
    this.title,
    this.currentMeasure,
    this.onReady,
  });

  @override
  State<OsmdSheetWidget> createState() => _OsmdSheetWidgetState();
}

class _OsmdSheetWidgetState extends State<OsmdSheetWidget> {
  late final String _viewId;
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'osmd-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
  }

  void _registerView() {
    if (_isRegistered) return;
    
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => _createOsmdContainer(),
    );
    _isRegistered = true;
  }

  web.HTMLDivElement _createOsmdContainer() {
    final container = web.document.createElement('div') as web.HTMLDivElement;
    container.id = _viewId;
    container.style
      ..width = '100%'
      ..height = '100%'
      ..overflow = 'auto'
      ..backgroundColor = '#ffffff';

    // 建立 OSMD 渲染區域
    final osmdDiv = web.document.createElement('div') as web.HTMLDivElement;
    osmdDiv.id = '${_viewId}-render';
    osmdDiv.style
      ..width = '100%'
      ..minHeight = '100%'
      ..padding = '20px';
    container.appendChild(osmdDiv);

    // 注入 OSMD 初始化腳本
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    final escapedXml = _escapeXml(widget.musicXml);
    
    script.text = '''
      (function() {
        var container = document.getElementById('${_viewId}-render');
        if (!container) {
          console.error('OSMD container not found');
          return;
        }
        
        if (typeof opensheetmusicdisplay === 'undefined') {
          container.innerHTML = '<p style="color: red; padding: 20px;">OpenSheetMusicDisplay 未載入，請重新整理頁面</p>';
          return;
        }
        
        try {
          var osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(container, {
            autoResize: true,
            drawTitle: true,
            drawSubtitle: false,
            drawComposer: true,
            drawCredits: true,
            drawPartNames: false,
            drawPartAbbreviations: false,
            drawMeasureNumbers: true,
            drawTimeSignatures: true,
            drawKeySignatures: true,
            renderSingleHorizontalStaffline: false,
            newSystemFromXML: true,
            newPageFromXML: true,
            backend: 'svg',
            drawingParameters: 'default'
          });
          
          var xmlContent = `$escapedXml`;
          
          osmd.load(xmlContent).then(function() {
            osmd.render();
            
            // 初始化游標
            osmd.cursor.show();
            osmd.cursor.reset();
            
            console.log('OSMD rendered successfully with cursor');
          }).catch(function(err) {
            console.error('OSMD load error:', err);
            container.innerHTML = '<p style="color: red; padding: 20px;">樂譜載入失敗: ' + err.message + '</p>';
          });
          
          // 儲存 OSMD 實例以便後續操作
          window['osmd_$_viewId'] = osmd;
        } catch (e) {
          console.error('OSMD init error:', e);
          container.innerHTML = '<p style="color: red; padding: 20px;">樂譜初始化失敗: ' + e.message + '</p>';
        }
      })();
    ''';
    
    // 延遲執行腳本，確保 DOM 已掛載
    Future.delayed(const Duration(milliseconds: 200), () {
      web.document.body?.appendChild(script);
    });

    return container;
  }

  String _escapeXml(String xml) {
    // 轉義反引號和特殊字符以便在 JS 模板字串中使用
    return xml
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');
  }

  @override
  void didUpdateWidget(OsmdSheetWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果 MusicXML 改變，重新渲染
    if (oldWidget.musicXml != widget.musicXml) {
      _reloadOsmd();
    }
    
    // 如果當前小節改變，更新游標位置
    if (oldWidget.currentMeasure != widget.currentMeasure && 
        widget.currentMeasure != null) {
      _updateCursor(widget.currentMeasure!);
    }
  }
  
  void _updateCursor(int measureIndex) {
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = '''
      (function() {
        var osmd = window['osmd_$_viewId'];
        if (!osmd || !osmd.cursor) return;
        
        try {
          // Hide cursor if measure is -1 (stopped)
          if ($measureIndex < 0) {
            osmd.cursor.hide();
            return;
          }
          
          // Show and reset cursor
          osmd.cursor.show();
          osmd.cursor.reset();
          
          // Move to target measure by iterating
          var targetMeasure = Math.max(0, $measureIndex);
          var iterations = 0;
          var maxIterations = 1000; // Safety limit
          
          while (iterations < maxIterations) {
            var currentMeasureIdx = osmd.cursor.iterator.currentMeasureIndex;
            
            if (currentMeasureIdx >= targetMeasure) {
              break;
            }
            
            if (!osmd.cursor.next()) {
              break; // End of score
            }
            
            iterations++;
          }
          
          // Force cursor update
          osmd.cursor.update();
          
          // Scroll cursor into view
          setTimeout(function() {
            var cursorElements = document.querySelectorAll('.cursor');
            if (cursorElements.length > 0) {
              var lastCursor = cursorElements[cursorElements.length - 1];
              lastCursor.scrollIntoView({ 
                behavior: 'smooth', 
                block: 'center',
                inline: 'center'
              });
            }
          }, 50);
          
        } catch (e) {
          console.error('Cursor update error:', e);
        }
      })();
    ''';
    web.document.body?.appendChild(script);
  }

  void _reloadOsmd() {
    final escapedXml = _escapeXml(widget.musicXml);
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = '''
      (function() {
        var osmd = window['osmd_$_viewId'];
        if (osmd) {
          var xmlContent = `$escapedXml`;
          osmd.load(xmlContent).then(function() {
            osmd.render();
          });
        }
      })();
    ''';
    web.document.body?.appendChild(script);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }

  @override
  void dispose() {
    // 清理 OSMD 實例
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = '''
      if (window['osmd_$_viewId']) {
        delete window['osmd_$_viewId'];
      }
    ''';
    web.document.body?.appendChild(script);
    super.dispose();
  }
}
