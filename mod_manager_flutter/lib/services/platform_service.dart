
abstract class PlatformService {
  Future<bool> sendF10ToGame();
  
  Future<bool> createModLink(String sourcePath, String linkPath);
  
  Future<bool> removeModLink(String linkPath);
  
  Future<bool> isModLink(String linkPath);
  
  String getAppDataPath();
  
  void showSetupInstructions();
  
  Future<bool> checkDependencies();
  
  Future<List<String>> findGameProcesses();
  
  String getDisplayServerType() => 'unknown';
  
  Future<bool> openUrlInBrowser(String url);
  
  String? getSystemDownloadsPath();
}
