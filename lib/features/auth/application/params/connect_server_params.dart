/// 文件输入：服务器地址、用户名、密码
/// 文件职责：封装连接服务器的请求参数
/// 文件对外接口：ConnectServerParams
/// 文件包含：ConnectServerParams
class ConnectServerParams {
  final String serverUrl;
  final String username;
  final String password;
  final bool rememberCredentials;

  const ConnectServerParams({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.rememberCredentials = true,
  });
}
