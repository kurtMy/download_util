import 'dart:io';

import 'package:dio/dio.dart';
import 'package:my_download/util/utils.dart';
import 'package:path_provider/path_provider.dart';

class DownloadManager {
  factory DownloadManager() => _instance;
  static final DownloadManager _instance = DownloadManager._internal();

  DownloadManager._internal();

  Map<String, DownloadInfo> downloadQueue = {};

  void downLoadFileDelete() async {
    String? downloadPath = await getDownloadPath();
    if(downloadPath != null) {
      Directory directory = Directory(downloadPath + "/download");
      Stream<FileSystemEntity> stream = directory.list(recursive: true);
      await for(FileSystemEntity entity in stream) {
        if(entity is File) {
          DateTime dateTime = await entity.lastModified();
          DateTime nowDateTime = DateTime.now();
          if(nowDateTime.difference(dateTime).inDays >= 30){
            print("delete path = " + entity.parent.path);
            if(entity.parent.path != directory.path) {
              entity.parent.delete(recursive: true);
            } else {
              entity.delete();
            }
          }
        }
        if(entity is Directory) {

        }
      }
    }
  }

  Future<Response> downloadWithChunk(String url, String path,
      {int? progress,
        ProgressCallback? progressCallback,
        Options? options,
        CancelToken? cancelToken}) async {
    String tempPath = path + "temp";
    DownloadInfo downloadInfo =
        downloadQueue[url] ?? DownloadInfo(url, path, 0, cancelToken??CancelToken());
    downloadQueue[url] = downloadInfo;
    if (downloadInfo.cancelToken.isCancelled) {
      downloadInfo.cancelToken = CancelToken();
    }
    progress ??= await downloadProgress(path);
    int startIndex = downloadInfo.progress = progress;
    print("start = $startIndex");
    try {
      Response response = await Dio().download(url, tempPath,
          onReceiveProgress: (received, total) {
            downloadInfo.progress + received;
            print("received = $received");
            if(progressCallback != null) {
              progressCallback(downloadInfo.progress + received, total);
            }
          },
          cancelToken: downloadInfo.cancelToken,
          options: Options(
              receiveTimeout: 0, headers: {"range": "bytes=$startIndex-"}),
          deleteOnError: false);
      if(response.statusCode == HttpStatus.partialContent) {
        downloadQueue.remove(url);
      }
      print("response = $response");
      await mergeFile(tempPath, path, path);
      return response;
    } on DioError catch (e) {
      print("request error =");
      print("data = ${e.response?.data}");
      print("headers = ${e.response?.headers}");
      print("response = ${e.response?.requestOptions}");
      // Something happened in setting up or sending the request that triggered an Error
      print("requestOptions = ${e.requestOptions}");
      print("message = ${e.message}");
      await mergeFile(tempPath, path, path);
      return Future.error(e);
    } catch (e) {
      print("request error =");
      return Future.error(e);
    }
  }

  void cancel(String url) async {
    CancelToken? cancelToken = downloadQueue[url]?.cancelToken;
    if(cancelToken == null || cancelToken.isCancelled) {
      return;
    }
    cancelToken.cancel();
  }

  Future<String> mergeFile(
      String tempPath, String path, String targetPath) async {
    File normalFile = File(path);
    IOSink sink;
    if (normalFile.existsSync()) {
      sink = normalFile.openWrite(mode: FileMode.append);
    } else {
      normalFile.createSync(recursive: true);
      sink = normalFile.openWrite(mode: FileMode.append);
    }
    File tempFile = File(tempPath);
    if (!tempFile.existsSync()) {
      return targetPath;
    }
    await sink.addStream(tempFile.openRead());
    await tempFile.delete();
    await sink.close();
    await normalFile.rename(targetPath);

    return targetPath;
  }

  Future<String?> getDownloadPath() async {
    Directory? directory = Utils.isAndroid()
        ? await getExternalStorageDirectory()
        : await getApplicationSupportDirectory();
    return directory?.path;
  }

  Future<int> downloadProgress(String path) async {
    String resultPath = await mergeFile(path + "temp", path, path);
    File normalFile = File(resultPath);
    int length = await normalFile.length();
    return length;
  }
}

class DownloadInfo {
  String url;
  String path;
  int progress;
  CancelToken token;

  DownloadInfo(this.url, this.path, this.progress, this.token);

  set downloadPath(String path) => this.path = path;

  String get downloadPath => path;

  set alreadyProgress(int progress) => this.progress = progress;

  int get alreadyProgress => progress;

  set cancelToken(CancelToken cancelToken) => token = cancelToken;

  CancelToken get cancelToken => token;
}
