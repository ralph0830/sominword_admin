import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '관리자 페이지',
      theme: ThemeData(
        fontFamily: 'NotoSansKR', // 기본 폰트 적용
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          final user = snapshot.data!;
          
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('account')
                .doc(user.email)
                .get(),
            builder: (context, adminSnapshot) {
              if (adminSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              // Firestore account 문서가 없으면 자동 생성
              if (adminSnapshot.data == null || !adminSnapshot.data!.exists) {
                FirebaseFirestore.instance.collection('account').doc(user.email).set({
                  'uid': user.uid,
                  'email': user.email,
                  'isApproved': false,
                  'isSuperAdmin': false,
                  'requestedAt': FieldValue.serverTimestamp(),
                });
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              final adminData = adminSnapshot.data?.data() as Map<String, dynamic>?;
              final isSuperAdmin = adminData?['isSuperAdmin'] == true;
              final isApproved = adminData?['isApproved'] ?? false;
              final email = adminData?['email'] as String?;
              
              debugPrint('🔍 [DEBUG] AuthWrapper: Admin 문서 존재:  [33m${adminSnapshot.data?.exists} [0m');
              debugPrint('🔍 [DEBUG] AuthWrapper: Admin 데이터: $adminData');
              debugPrint('🔍 [DEBUG] AuthWrapper: isSuperAdmin: $isSuperAdmin, isApproved: $isApproved');
              
              if (isApproved) {
                return DeviceListPage(isSuperAdmin: isSuperAdmin, email: email);
              } else {
                FirebaseAuth.instance.signOut();
                return const LoginPage();
              }
            },
          );
        }
        
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceIdController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  String? _errorMessage;
  
  // 전역 에러 메시지 저장용
  static String? _globalErrorMessage;
  static bool _globalIsLoading = false;
  
  @override
  void initState() {
    super.initState();
    // 전역 상태 복원
    if (_globalErrorMessage != null) {
      _errorMessage = _globalErrorMessage;
      _globalErrorMessage = null; // 한 번 사용 후 초기화
    }
    _isLoading = _globalIsLoading;
    _globalIsLoading = false;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      // mounted가 false인 경우 전역 상태 사용
      _globalIsLoading = true;
      _globalErrorMessage = null;
    }

    try {
      debugPrint('🔍 [DEBUG] 로그인 시도: ${_emailController.text.trim()}');
      
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      debugPrint('🔍 [DEBUG] Firebase Auth 성공: ${userCredential.user?.email}');
      debugPrint('🔍 [DEBUG] User UID: ${userCredential.user?.uid}');

      // 슈퍼 관리자 확인
      if (userCredential.user?.email == 'ralph0830@gmail.com') {
        debugPrint('🔍 [DEBUG] 슈퍼 관리자로 인식됨');
        // 슈퍼 관리자는 바로 접근 가능
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      debugPrint('🔍 [DEBUG] 일반 관리자 확인 중...');

      // 일반 관리자 승인 상태 확인
      final adminDoc = await FirebaseFirestore.instance
          .collection('account')
          .doc(userCredential.user!.email)
          .get();

      debugPrint('🔍 [DEBUG] Admin 문서 존재: ${adminDoc.exists}');
      if (adminDoc.exists) {
        final adminData = adminDoc.data();
        debugPrint('🔍 [DEBUG] Admin 데이터: $adminData');
        debugPrint('🔍 [DEBUG] isApproved 값: ${adminData?['isApproved']}');
      }

      if (!adminDoc.exists || !(adminDoc.data()?['isApproved'] ?? false)) {
        debugPrint('🔍 [DEBUG] 승인되지 않은 관리자 - 전역 에러 메시지 설정 후 로그아웃');
        
        // 전역 에러 메시지 설정
        _globalErrorMessage = '관리자 승인이 되지 않은 아이디 입니다. 관리자에게 문의 바랍니다.';
        debugPrint('🔍 [DEBUG] 전역 에러 메시지 설정: $_globalErrorMessage');
        
        // 로그아웃 (AuthWrapper가 LoginPage로 돌아가도록)
        await FirebaseAuth.instance.signOut();
        debugPrint('🔍 [DEBUG] 로그아웃 완료');
        return;
      }
      
      debugPrint('🔍 [DEBUG] 승인된 관리자 - 로그인 성공');
      // 로그인 성공 시
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    } on FirebaseAuthException catch (e) {
      debugPrint('🔍 [DEBUG] FirebaseAuthException 발생: ${e.code} - ${e.message}');
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = '등록되지 않은 이메일입니다.';
          break;
        case 'wrong-password':
          message = '잘못된 비밀번호입니다.';
          break;
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        case 'weak-password':
          message = '비밀번호가 너무 약합니다.';
          break;
        case 'email-already-in-use':
          message = '이미 사용 중인 이메일입니다.';
          break;
        default:
          message = '로그인 실패: ${e.message}';
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      }
      } catch (e) {
      debugPrint('🔍 [DEBUG] 일반 Exception 발생: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '오류가 발생했습니다: $e';
        });
      }
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // 이메일과 기기 ID 유효성 검사
      final email = _emailController.text.trim();
      final deviceId = _deviceIdController.text.trim();

      if (email.isEmpty || deviceId.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '이메일과 기기 고유번호를 모두 입력해주세요.';
          });
        }
        return;
      }

      // 기기 존재 여부 확인
      final deviceDoc = await FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .get();

      if (!deviceDoc.exists) {
        if (mounted) {
          setState(() {
            _errorMessage = '유효하지 않은 기기 고유번호입니다. 앱에서 확인한 번호를 정확히 입력해주세요.';
          });
        }
        return;
      }

      // 계정 생성
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );

      // Firestore account 문서 생성 (uid, email 동기화)
      await FirebaseFirestore.instance
          .collection('account')
          .doc(userCredential.user!.email)
          .set({
        'uid': userCredential.user!.uid,
        'email': email,
        'deviceId': deviceId,
        'deviceName': deviceDoc.data()?['deviceName'] ?? 'Unknown Device',
        'isApproved': false,
        'isSuperAdmin': false,
        'requestedAt': FieldValue.serverTimestamp(),
        'approvedAt': null,
        'approvedBy': null,
      });

      // 로그아웃 (승인 대기 상태)
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        setState(() {
          _errorMessage = '관리자 신청이 완료되었습니다. 슈퍼 관리자의 승인을 기다려주세요.';
          _isSignUp = false;
        });
      }

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = '비밀번호가 너무 약합니다.';
          break;
        case 'email-already-in-use':
          message = '이미 사용 중인 이메일입니다.';
          break;
        case 'invalid-email':
          message = '유효하지 않은 이메일 형식입니다.';
          break;
        default:
          message = '회원가입 실패: ${e.message}';
      }
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '오류가 발생했습니다: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? '관리자 신청' : '관리자 로그인'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Icon(
                _isSignUp ? Icons.person_add : Icons.admin_panel_settings,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 32),
              Text(
                _isSignUp ? '관리자 신청' : '관리자 로그인',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isSignUp 
                  ? '기기별 단어를 관리할 수 있는 권한을 신청합니다.'
                  : '슈퍼 관리자 또는 승인된 관리자만 접근할 수 있습니다.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '이메일을 입력해주세요.';
                  }
                  if (!value.contains('@')) {
                    return '유효한 이메일 형식을 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_isSignUp) ...[
                TextFormField(
                  controller: _deviceIdController,
                  decoration: const InputDecoration(
                    labelText: '기기 고유번호',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.device_hub),
                    hintText: '앱에서 확인한 기기 고유번호를 입력하세요',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '기기 고유번호를 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                onFieldSubmitted: (value) {
                  if (!_isLoading) {
                    _isSignUp ? _signUp() : _signIn();
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력해주세요.';
                  }
                  if (value.length < 6) {
                    return '비밀번호는 6자 이상이어야 합니다.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade300, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning, color: Colors.red.shade600, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '로그인 오류',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  const SizedBox(height: 8),
                      Text(
                        '🔍 [DEBUG] _errorMessage: $_errorMessage',
                        style: const TextStyle(color: Colors.blue, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_isSignUp ? _signUp : _signIn),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(_isSignUp ? '관리자 신청' : '로그인'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSignUp = !_isSignUp;
                    _errorMessage = null;
                    _emailController.clear();
                    _passwordController.clear();
                    _deviceIdController.clear();
                  });
                },
                child: Text(_isSignUp ? '이미 계정이 있으신가요? 로그인' : '관리자 신청하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceListPage extends StatelessWidget {
  final bool isSuperAdmin;
  final String? email;
  const DeviceListPage({super.key, required this.isSuperAdmin, this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기기별 단어 관리'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (isSuperAdmin)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('pendingDevices').snapshots(),
              builder: (context, pendingSnapshot) {
                final pendingCount = pendingSnapshot.data?.docs.length ?? 0;
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('account').where('isApproved', isEqualTo: false).snapshots(),
                  builder: (context, adminSnapshot) {
                    final adminCount = adminSnapshot.data?.docs.length ?? 0;
                    final totalCount = pendingCount + adminCount;
                    return Row(
                      children: [
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.admin_panel_settings),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AdminManagementPage()),
                                );
                              },
                              tooltip: '관리자 승인 관리',
                            ),
                            if (totalCount > 0)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$totalCount',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.verified_user),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const DeviceApprovalStatusPage()),
                            );
                          },
                          tooltip: '기기별 승인 현황',
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            tooltip: '로그아웃',
          ),
        ],
      ),
      floatingActionButton: !isSuperAdmin && email != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('기기 추가 신청'),
              onPressed: () => _showDeviceRequestDialog(context, email!),
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: isSuperAdmin
            ? FirebaseFirestore.instance
                .collection('devices')
                .orderBy('lastActiveAt', descending: true)
                .snapshots()
            : (email != null
                ? FirebaseFirestore.instance
                    .collection('devices')
                    .where('ownerEmail', isEqualTo: email)
                    .snapshots()
                : const Stream.empty()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }
          
          final devices = snapshot.data?.docs ?? [];
          
          if (devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('등록된 기기가 없습니다.', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('앱을 실행하면 기기가 등록됩니다.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index].data() as Map<String, dynamic>;
              final deviceId = devices[index].id;
              final deviceName = device['deviceName'] ?? 'Unknown Device';
              final nickname = device['nickname'] ?? '';
              final lastActive = device['lastActiveAt'] as Timestamp?;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.phone_android, size: 32),
                  title: Row(
                    children: [
                      Expanded(child: Text(deviceName)),
                      if (nickname.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text('닉네임: $nickname', style: const TextStyle(color: Colors.deepPurple)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        tooltip: '닉네임 수정',
                        onPressed: () {
                          _showEditNicknameDialog(context, deviceId, nickname);
                        },
                      ),
                      // [수정] 일반 관리자만 보이는 '다른 기기로 단어 복사' 버튼 (보라색 복사 아이콘)
                      if (!isSuperAdmin && email != null)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20, color: Colors.deepPurple),
                          tooltip: '다른 기기로 단어 복사',
                          onPressed: () {
                            _showCopyWordsDialog(context, deviceId, deviceName);
                          },
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              'ID: $deviceId',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                            ),
                          ),
                          if (isSuperAdmin)
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20, color: Colors.deepPurple),
                              tooltip: '다른 기기로 단어 복사',
                              onPressed: () {
                                _showCopyWordsDialog(context, deviceId, deviceName);
                              },
                            ),
                        ],
                      ),
                      // [변경] 단어 개수는 모든 사용자에게 표시
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('devices').doc(deviceId).collection('words').snapshots(),
                        builder: (context, wordSnap) {
                          final count = wordSnap.data?.docs.length ?? 0;
                          return Text('단어: $count개', style: const TextStyle(color: Colors.deepPurple));
                        },
                      ),
                      if (lastActive != null)
                        Text('마지막 활동: ${_formatDate(lastActive.toDate())}'),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WordAdminPage(
                          deviceId: deviceId,
                          deviceName: deviceName,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
  
  void _showEditNicknameDialog(BuildContext context, String deviceId, String currentNickname) {
    final controller = TextEditingController(text: currentNickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기기 닉네임 수정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '닉네임',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newNickname = controller.text.trim();
              await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'nickname': newNickname});
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  void _showDeviceRequestDialog(BuildContext context, String email) {
    final deviceIdController = TextEditingController();
    final deviceNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기기 추가 신청'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: deviceIdController,
              decoration: const InputDecoration(
                labelText: '기기 고유번호',
                border: OutlineInputBorder(),
                hintText: '앱에서 확인한 기기 고유번호를 입력하세요',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: deviceNameController,
              decoration: const InputDecoration(
                labelText: '기기 이름',
                border: OutlineInputBorder(),
                hintText: '예: android, Web Browser 등',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final deviceId = deviceIdController.text.trim();
              debugPrint('[DEBUG] 입력된 deviceId: $deviceId');

              // Firestore에서 해당 deviceId 문서 조회
              final deviceDoc = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();

              if (!deviceDoc.exists) {
                debugPrint('[DEBUG] 입력된 deviceId가 Firestore에 존재하지 않음.');
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('등록된 고유 번호가 아닙니다. 앱을 기기에서 최소 1회 실행해주세요.')),
                );
                return;
              }

              final data = deviceDoc.data();
              debugPrint('[DEBUG] Firestore에서 조회된 device 데이터: ${data.toString()}');

              if (data?['ownerEmail'] != null && (data?['ownerEmail'] as String).isNotEmpty) {
                debugPrint('[DEBUG] 이미 ownerEmail이 존재함: ${data?['ownerEmail']}');
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('이미 등록된 번호입니다.')),
                );
                return;
              }

              final deviceName = data?['deviceName'] ?? 'Unknown Device';
              debugPrint('[DEBUG] Firestore에서 가져온 deviceName: $deviceName');

              await FirebaseFirestore.instance.collection('pendingDevices').add({
                'deviceId': deviceId,
                'deviceName': deviceName,
                'ownerEmail': email,
                'requestedAt': FieldValue.serverTimestamp(),
              });
              debugPrint('[DEBUG] pendingDevices에 신청 완료: deviceId=$deviceId, deviceName=$deviceName, ownerEmail=$email');
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('기기 추가 신청이 완료되었습니다. 슈퍼 관리자의 승인을 기다려주세요.')),
              );
            },
            child: const Text('신청'),
          ),
        ],
      ),
    );
  }

  void _showCopyWordsDialog(BuildContext context, String fromDeviceId, String fromDeviceName) async {
    // 본인 소유 기기 목록 조회
    final devicesSnapshot = await FirebaseFirestore.instance
        .collection('devices')
        .where('ownerEmail', isEqualTo: email)
        .get();
    if (!context.mounted) return; // [추가] async gap 후 context 사용 보호
    final devices = devicesSnapshot.docs
        .where((doc) => doc.id != fromDeviceId)
        .toList();
    if (devices.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => const AlertDialog(
          title: Text('단어 복사'),
          content: Text('복사할 대상 기기가 없습니다.'),
        ),
      );
      return;
    }
    String? selectedDeviceId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('다른 기기로 단어 복사'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('[$fromDeviceName]의 단어를 복사할 기기를 선택하세요.'),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedDeviceId,
                hint: const Text('대상 기기 선택'),
                items: devices.map((doc) {
                  final data = doc.data();
                  final name = data['deviceName'] ?? doc.id;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text('$name (${doc.id})'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedDeviceId = val;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: selectedDeviceId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      // [추가] async gap 이후 context 사용 보호
                      if (!context.mounted) return;
                      await _copyWordsToDevice(context, fromDeviceId, selectedDeviceId!, fromDeviceName, selectedDeviceId!);
                    },
              child: const Text('복사'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyWordsToDevice(BuildContext context, String fromDeviceId, String toDeviceId, String fromDeviceName, String toDeviceName) async {
    final firestore = FirebaseFirestore.instance;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text('단어 복사 중...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('단어를 복사하고 있습니다.'),
          ],
        ),
      ),
    );
    try {
      final fromWordsSnap = await firestore.collection('devices/$fromDeviceId/words').get();
      if (fromWordsSnap.docs.isEmpty) {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('복사할 단어가 없습니다.')),
          );
        }
        return;
      }
      final toWordsSnap = await firestore.collection('devices/$toDeviceId/words').get();
      final toWords = toWordsSnap.docs.map((d) => d.data()['englishWord'] as String?).toSet();
      int copied = 0;
      final batch = firestore.batch();
      for (final doc in fromWordsSnap.docs) {
        final data = doc.data();
        final eng = data['englishWord'] ?? data['englishWord'] ?? data['eng'] ?? '';
        if (eng.isEmpty || toWords.contains(eng)) continue; // 중복 방지
        final newDoc = firestore.collection('devices/$toDeviceId/words').doc();
        batch.set(newDoc, data);
        copied++;
      }
      await batch.commit();
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$fromDeviceName]의 단어 $copied개가 [$toDeviceName]로 복사되었습니다.'),),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복사 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class WordAdminPage extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  
  const WordAdminPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<WordAdminPage> createState() => _WordAdminPageState();
}

class _WordAdminPageState extends State<WordAdminPage> {
  // [삭제] 더 이상 사용되지 않는 필드 제거
  // final _formKey = GlobalKey<FormState>();
  // final TextEditingController _engController = TextEditingController();
  // final TextEditingController _posController = TextEditingController();
  // final TextEditingController _korController = TextEditingController();

  String get _wordsPath => 'devices/${widget.deviceId}/words';

  // [추가] 선택된 단어 ID 목록
  final Set<String> _selectedWordIds = {};

  void _handleCsvAddResult(BuildContext dialogContext, int success, int duplicate, int fail) {
    Navigator.of(dialogContext).pop();
    if (dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text('완료: 성공 $success개, 중복 $duplicate개, 실패 $fail개'),
        ),
      );
    }
  }

  void _showCsvDialog() {
    final csvController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV 붙여넣기 (영어,품사,뜻)'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: csvController,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '예시: apple,명사,사과\nrun,동사,달리다',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final lines = csvController.text.trim().split('\n');
              int success = 0, duplicate = 0, fail = 0;
              for (final line in lines) {
                if (line.trim().isEmpty) continue;
                final parts = line.split(',');
                if (parts.length < 3) {
                  fail++;
                  continue;
                }
                final eng = parts[0].trim();
                final pos = parts[1].trim();
                final kor = parts[2].trim();
                // [추가] 예문, 예문해석은 없으면 null로 처리
                final sentence = parts.length > 3 ? parts[3].trim() : null;
                final sentenceKor = parts.length > 4 ? parts[4].trim() : null;
                try {
                  final dup = await FirebaseFirestore.instance
                      .collection(_wordsPath)
                      .where('englishWord', isEqualTo: eng)
                      .get();
                  if (dup.docs.isNotEmpty) {
                    duplicate++;
                    continue;
                  }
                  await FirebaseFirestore.instance.collection(_wordsPath).add({
                    'englishWord': eng,
                    'koreanPartOfSpeech': pos,
                    'koreanMeaning': kor,
                    'sentence': sentence,
                    'sentenceKor': sentenceKor,
                    'inputTimestamp': FieldValue.serverTimestamp(),
                  });
                  success++;
                } catch (e) {
                  fail++;
                }
              }
              if (ctx.mounted) {
                _handleCsvAddResult(ctx, success, duplicate, fail);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  // 테스트용 단어 데이터 생성
  // Future<void> _addTestWords() async {
  //   debugPrint('🔍 [DEBUG] 테스트 단어 추가 시작');
    
  //   final testWords = [
  //     {'english': 'apple', 'pos': '명사', 'meaning': '사과'},
  //     {'english': 'run', 'pos': '동사', 'meaning': '달리다'},
  //     {'english': 'beautiful', 'pos': '형용사', 'meaning': '아름다운'},
  //     {'english': 'quickly', 'pos': '부사', 'meaning': '빠르게'},
  //     {'english': 'book', 'pos': '명사', 'meaning': '책'},
  //   ];
    
  //   int success = 0;
  //   int duplicate = 0;
    
  //   for (final word in testWords) {
  //     try {
  //       debugPrint('🔍 [DEBUG] 테스트 단어 추가 중: ${word['english']}');
        
  //       // 중복 체크
  //       final dup = await FirebaseFirestore.instance
  //           .collection(_wordsPath)
  //           .where('englishWord', isEqualTo: word['english'])
  //           .get();
        
  //       if (dup.docs.isNotEmpty) {
  //         debugPrint('🔍 [DEBUG] 중복 단어: ${word['english']}');
  //         duplicate++;
  //         continue;
  //       }
        
  //       // 단어 추가
  //       final docRef = await FirebaseFirestore.instance.collection(_wordsPath).add({
  //         'englishWord': word['english'],
  //         'koreanPartOfSpeech': word['pos'],
  //         'koreanMeaning': word['meaning'],
  //         'inputTimestamp': FieldValue.serverTimestamp(),
  //         'isFavorite': false,
  //       });
        
  //       debugPrint('🔍 [DEBUG] 테스트 단어 추가 완료: ${word['english']} (ID: ${docRef.id})');
  //       success++;
        
  //     } catch (e) {
  //       debugPrint('🔍 [DEBUG] 테스트 단어 추가 실패: ${word['english']} - $e');
  //     }
  //   }
    
  //   debugPrint('�� [DEBUG] 테스트 단어 추가 완료 - 성공: $success, 중복: $duplicate');
    
  //   if (mounted) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('테스트 단어 추가 완료: 성공 $success개, 중복 $duplicate개'),
  //         duration: const Duration(seconds: 3),
  //       ),
  //     );
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deviceName} - 단어 관리'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // [추가] 단어 추가 버튼
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '단어 추가',
            onPressed: _showAddWordDialog,
          ),
          // [추가] 선택 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '선택 삭제',
            onPressed: _selectedWordIds.isEmpty ? null : _deleteSelectedWords,
          ),
          // [추가] 선택 복사 버튼
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '선택 복사',
            onPressed: _selectedWordIds.isEmpty ? null : _showCopySelectedWordsDialog,
          ),
          // [삭제] 테스트 단어 추가 버튼 제거
          // IconButton(
          //   icon: const Icon(Icons.science),
          //   onPressed: _addTestWords,
          //   tooltip: '테스트 단어 추가',
          // ),
          // [추가] TSV 대량 추가 버튼
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _showTsvDialog,
            tooltip: 'TSV 대량 추가',
          ),
        ],
      ),
      body: Column(
          children: [
          // 단어 목록
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                  .collection(_wordsPath)
                  .orderBy('inputTimestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                
                if (snapshot.hasError) {
                  return Center(child: Text('오류: ${snapshot.error}'));
                }
                
                final words = snapshot.data?.docs ?? [];
                
                if (words.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.book, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('등록된 단어가 없습니다.', style: TextStyle(fontSize: 18)),
                        SizedBox(height: 8),
                        Text('위 폼에서 단어를 추가해보세요.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                
                  return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    final word = words[index].data() as Map<String, dynamic>;
                    final wordId = words[index].id;
                    final englishWord = word['englishWord'] ?? '';
                    final koreanPartOfSpeech = word['koreanPartOfSpeech'] ?? '';
                    final koreanMeaning = word['koreanMeaning'] ?? '';
                    final inputTimestamp = word['inputTimestamp'] as Timestamp?;
                    final isSelected = _selectedWordIds.contains(wordId);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        // [변경] 체크박스 추가, 별표 제거
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedWordIds.add(wordId);
                              } else {
                                _selectedWordIds.remove(wordId);
                              }
                            });
                          },
                        ),
                        title: Text(
                          englishWord,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$koreanPartOfSpeech $koreanMeaning'),
                            if (inputTimestamp != null)
                              Text(
                                _formatDate(inputTimestamp.toDate()),
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              _showEditDialog(wordId, englishWord, koreanPartOfSpeech, koreanMeaning);
                            } else if (value == 'delete') {
                              _showDeleteDialog(wordId, englishWord);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('수정'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('삭제', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // [추가] 단어 추가 다이얼로그
  void _showAddWordDialog() {
    final engController = TextEditingController();
    final posController = TextEditingController();
    final korController = TextEditingController();
    final sentenceController = TextEditingController();
    final sentenceKorController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('단어 추가'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: engController,
                  decoration: const InputDecoration(labelText: '영어 단어'),
                  validator: (v) => v == null || v.isEmpty ? '영어 단어 입력' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: posController,
                  decoration: const InputDecoration(labelText: '품사'),
                  validator: (v) => v == null || v.isEmpty ? '품사 입력' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: korController,
                  decoration: const InputDecoration(labelText: '한글 뜻'),
                  validator: (v) => v == null || v.isEmpty ? '한글 뜻 입력' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: sentenceController,
                  decoration: const InputDecoration(labelText: '예문 (선택)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: sentenceKorController,
                  decoration: const InputDecoration(labelText: '예문 해석 (선택)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          // [추가] CSV/TSV 삽입 버튼
          TextButton(
            onPressed: _showCsvDialog,
            child: const Text('CSV 붙여넣기'),
          ),
          TextButton(
            onPressed: _showTsvDialog,
            child: const Text('TSV 붙여넣기'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final eng = engController.text.trim();
              final pos = posController.text.trim();
              final kor = korController.text.trim();
              final sentence = sentenceController.text.trim().isEmpty ? null : sentenceController.text.trim();
              final sentenceKor = sentenceKorController.text.trim().isEmpty ? null : sentenceKorController.text.trim();
              // [중복 체크]
              final dup = await FirebaseFirestore.instance
                  .collection(_wordsPath)
                  .where('englishWord', isEqualTo: eng)
                  .get();
              if (dup.docs.isNotEmpty) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('이미 등록된 단어입니다.')),
                  );
                }
                return;
              }
              // [단어 추가]
              await FirebaseFirestore.instance.collection(_wordsPath).add({
                'englishWord': eng,
                'koreanPartOfSpeech': pos,
                'koreanMeaning': kor,
                'sentence': sentence,
                'sentenceKor': sentenceKor,
                'inputTimestamp': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('단어가 추가되었습니다.')),
                );
              }
              setState(() {});
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
  
  void _showEditDialog(String wordId, String englishWord, String koreanPartOfSpeech, String koreanMeaning) {
    final engController = TextEditingController(text: englishWord);
    final posController = TextEditingController(text: koreanPartOfSpeech);
    final korController = TextEditingController(text: koreanMeaning);
    
    showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('단어 수정'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
              controller: engController,
                                          decoration: const InputDecoration(labelText: '영어 단어'),
                                        ),
                                        TextField(
              controller: posController,
                                          decoration: const InputDecoration(labelText: '품사'),
                                        ),
                                        TextField(
              controller: korController,
                                          decoration: const InputDecoration(labelText: '한글 뜻'),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('취소'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
              await FirebaseFirestore.instance
                  .collection(_wordsPath)
                  .doc(wordId)
                  .update({
                'englishWord': engController.text.trim(),
                'koreanPartOfSpeech': posController.text.trim(),
                'koreanMeaning': korController.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) {
                Navigator.pop(ctx);
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(content: Text('단어가 수정되었습니다.')),
                                            );
              }
            },
            child: const Text('수정'),
                                      ),
                                    ],
                                  ),
                                );
  }
  
  void _showDeleteDialog(String wordId, String englishWord) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('단어 삭제'),
        content: Text('"$englishWord" 단어를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
                              onPressed: () async {
              await FirebaseFirestore.instance
                  .collection(_wordsPath)
                  .doc(wordId)
                  .delete();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('단어가 삭제되었습니다.')),
                                  );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // [추가] 선택된 단어 일괄 삭제
  Future<void> _deleteSelectedWords() async {
    if (_selectedWordIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('선택 삭제'),
        content: Text('선택한 ${_selectedWordIds.length}개의 단어를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirm != true) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final wordId in _selectedWordIds) {
      final ref = FirebaseFirestore.instance.collection(_wordsPath).doc(wordId);
      batch.delete(ref);
    }
    await batch.commit();
    setState(() {
      _selectedWordIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('선택한 단어 ${_selectedWordIds.length}개가 삭제되었습니다.')),
      );
    }
  }

  // [추가] 선택된 단어 복사 다이얼로그
  void _showCopySelectedWordsDialog() async {
    // 본인 소유 기기 목록 조회
    final devicesSnapshot = await FirebaseFirestore.instance
        .collection('devices')
        .get();
    final devices = devicesSnapshot.docs
        .where((doc) => doc.id != widget.deviceId)
        .toList();
    if (devices.isEmpty) {
      // builder의 ctx만 사용
      await showDialog(
        context: context,
        builder: (ctx) => const AlertDialog(
          title: Text('단어 복사'),
          content: Text('복사할 대상 기기가 없습니다.'),
        ),
      );
      return;
    }
    String? selectedDeviceId;
    // showDialog를 await로 받아서 복사 실행
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('선택한 단어 복사'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('선택한 단어를 복사할 기기를 선택하세요.'),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedDeviceId,
                hint: const Text('대상 기기 선택'),
                items: devices.map((doc) {
                  final data = doc.data();
                  final name = data['deviceName'] ?? doc.id;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text('$name (${doc.id})'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedDeviceId = val;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: selectedDeviceId == null
                  ? null
                  : () => Navigator.pop(ctx, selectedDeviceId),
              child: const Text('복사'),
            ),
          ],
        ),
      ),
    );
    // async gap 이후 context 사용 전 반드시 mounted 체크
    if (!mounted) return;
    if (result != null) {
      if (!mounted) return; // await 이후 context 사용 전 추가 체크
      _handleCopySelectedWords(result, devices);
    }
  }

  // async gap 이후 context 사용을 분리한 함수
  Future<void> _handleCopySelectedWords(String toDeviceId, List devices) async {
    final toDeviceName = devices.firstWhere((d) => d.id == toDeviceId).data()['deviceName'] ?? toDeviceId;
    await _copySelectedWordsToDevice(toDeviceId, toDeviceName);
  }

  // [추가] 선택된 단어 복사 실행
  Future<void> _copySelectedWordsToDevice(String toDeviceId, String toDeviceName) async {
    final firestore = FirebaseFirestore.instance;
    final selectedWordsSnap = await firestore.collection(_wordsPath).where(FieldPath.documentId, whereIn: _selectedWordIds.toList()).get();
    final toWordsSnap = await firestore.collection('devices/$toDeviceId/words').get();
    final toWords = toWordsSnap.docs.map((d) => d.data()['englishWord'] as String?).toSet();
    int copied = 0;
    final batch = firestore.batch();
    for (final doc in selectedWordsSnap.docs) {
      final data = doc.data();
      final eng = data['englishWord'] ?? '';
      if (eng.isEmpty || toWords.contains(eng)) continue; // 중복 방지
      final newDoc = firestore.collection('devices/$toDeviceId/words').doc();
      batch.set(newDoc, data);
      copied++;
    }
    await batch.commit();
    if (!mounted) return; // setState와 context 사용 전 mounted 체크
    setState(() {
      _selectedWordIds.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('선택한 단어 $copied개가 [$toDeviceName]로 복사되었습니다.')),
      );
    }
  }

  // [추가] TSV 붙여넣기 다이얼로그
  void _showTsvDialog() {
    final tsvController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TSV 붙여넣기 (영어\t품사\t뜻)'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: tsvController,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '예시: apple\t명사\t사과\trun\t동사\t달리다',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final lines = tsvController.text.trim().split('\n');
              int success = 0, duplicate = 0, fail = 0;
              for (final line in lines) {
                if (line.trim().isEmpty) continue;
                final parts = line.split('\t');
                if (parts.length < 3) {
                  fail++;
                  continue;
                }
                final eng = parts[0].trim();
                final pos = parts[1].trim();
                final kor = parts[2].trim();
                // [추가] 예문, 예문해석은 없으면 null로 처리
                final sentence = parts.length > 3 ? parts[3].trim() : null;
                final sentenceKor = parts.length > 4 ? parts[4].trim() : null;
                try {
                  final dup = await FirebaseFirestore.instance
                      .collection(_wordsPath)
                      .where('englishWord', isEqualTo: eng)
                      .get();
                  if (dup.docs.isNotEmpty) {
                    duplicate++;
                    continue;
                  }
                  await FirebaseFirestore.instance.collection(_wordsPath).add({
                    'englishWord': eng,
                    'koreanPartOfSpeech': pos,
                    'koreanMeaning': kor,
                    'sentence': sentence,
                    'sentenceKor': sentenceKor,
                    'inputTimestamp': FieldValue.serverTimestamp(),
                  });
                  success++;
                } catch (e) {
                  fail++;
                }
              }
              if (ctx.mounted) {
                _handleCsvAddResult(ctx, success, duplicate, fail);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}

class AdminManagementPage extends StatelessWidget {
  const AdminManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 승인 관리'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Pending Devices Section
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('pendingDevices').orderBy('requestedAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final pending = snapshot.data?.docs ?? [];
              if (pending.isEmpty) {
                return const SizedBox();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('기기 추가 신청', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ...pending.map((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    final deviceId = data?['deviceId'] ?? '';
                    final deviceName = data?['deviceName'] ?? '';
                    final ownerEmail = data?['ownerEmail'] ?? '';
                    final requestedAt = data?['requestedAt'] as Timestamp?;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.device_hub, size: 32),
                        title: Text('$deviceName ($deviceId)'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('신청자: $ownerEmail'),
                            if (requestedAt != null)
                              Text('신청일:  [33m${_formatDate(requestedAt.toDate())} [0m'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => _approveDevice(context, doc.id, deviceId, ownerEmail, deviceName: deviceName),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text('승인'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _rejectDevice(context, doc.id),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              child: const Text('거부'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          // 기존 관리자 승인 관리 UI
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('account')
                  .where('isSuperAdmin', isEqualTo: false)
                  .orderBy('requestedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('오류: ${snapshot.error}'));
                }
                
                final admins = snapshot.data?.docs ?? [];
                
                if (admins.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('관리자 신청/승인 내역이 없습니다.', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: admins.length,
                  itemBuilder: (context, index) {
                    final admin = admins[index].data() as Map<String, dynamic>?;
                    final adminId = admins[index].id;
                    final email = admin?['email'] ?? '';
                    final deviceId = admin?['deviceId'] ?? '';
                    final deviceName = admin?['deviceName'] ?? 'Unknown Device';
                    final isApproved = admin?['isApproved'] ?? false;
                    final requestedAt = admin?['requestedAt'] as Timestamp?;
                    final approvedAt = admin?['approvedAt'] as Timestamp?;
                    final approvedBy = admin?['approvedBy'] as String?;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          isApproved ? Icons.check_circle : Icons.pending,
                          color: isApproved ? Colors.green : Colors.orange,
                          size: 32,
                        ),
                        title: Text(email),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('기기: $deviceName'),
                            Text('기기 ID: $deviceId'),
                            if (requestedAt != null)
                              Text('신청일: ${_formatDate(requestedAt.toDate())}'),
                            if (isApproved && approvedAt != null)
                              Text('승인일: ${_formatDate(approvedAt.toDate())}'),
                            if (isApproved && approvedBy != null)
                              Text('승인자: $approvedBy'),
                          ],
                        ),
                        trailing: isApproved
                            ? const Chip(
                                label: Text('승인됨'),
                                backgroundColor: Colors.green,
                                labelStyle: TextStyle(color: Colors.white),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _approveAdmin(context, adminId, email),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('승인'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () => _rejectAdmin(context, adminId, email),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('거부'),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveDevice(BuildContext context, String pendingId, String deviceId, String ownerEmail, {String? deviceName}) async {
    try {
      final deviceRef = FirebaseFirestore.instance.collection('devices').doc(deviceId);
      final deviceSnap = await deviceRef.get();
      if (deviceSnap.exists) {
        await deviceRef.update({
          'ownerEmail': ownerEmail,
          if (deviceName != null) 'deviceName': deviceName,
        });
      } else {
        await deviceRef.set({
          'deviceId': deviceId,
          'deviceName': deviceName ?? 'Unknown',
          'ownerEmail': ownerEmail,
          'nickname': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // words 서브컬렉션에 apple(명사, 사과) 단어 추가
        await deviceRef.collection('words').add({
          'englishWord': 'apple',
          'koreanPartOfSpeech': '명사',
          'koreanMeaning': '사과',
          'inputTimestamp': FieldValue.serverTimestamp(),
          'isFavorite': false,
        });
        debugPrint('[DEBUG] words 서브컬렉션에 apple(명사, 사과) 단어 추가 완료: deviceId=$deviceId');
      }
      await FirebaseFirestore.instance.collection('pendingDevices').doc(pendingId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기기 추가가 승인되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('기기 승인 실패: $e')),
        );
      }
    }
  }

  Future<void> _rejectDevice(BuildContext context, String pendingId) async {
    try {
      await FirebaseFirestore.instance.collection('pendingDevices').doc(pendingId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기기 추가 신청이 거부되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('거부 실패: $e')),
        );
      }
    }
  }

  Future<void> _approveAdmin(BuildContext context, String adminId, String email) async {
    try {
      // account 문서에서 deviceId 또는 deviceIds 배열 가져오기
      final adminDoc = await FirebaseFirestore.instance.collection('account').doc(email).get();
      final adminData = adminDoc.data();
      final deviceId = adminData?['deviceId'];
      final deviceIds = adminData?['deviceIds'] as List<dynamic>?;

      // account 승인 처리
      await FirebaseFirestore.instance
          .collection('account')
          .doc(email)
          .update({
        'isApproved': true,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
      });

      // 여러 기기 확장: deviceIds 배열이 있으면 모두 ownerEmail 추가, 없으면 기존 deviceId 처리
      if (deviceIds != null && deviceIds.isNotEmpty) {
        for (final id in deviceIds) {
          await FirebaseFirestore.instance
              .collection('devices')
              .doc(id)
              .update({'ownerEmail': email});
        }
      } else if (deviceId != null) {
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .update({'ownerEmail': email});
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email 관리자가 승인되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('승인 실패: $e')),
        );
      }
    }
  }

  Future<void> _rejectAdmin(BuildContext context, String adminId, String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('account')
          .doc(email)
          .delete();
      
      // Firebase Auth 계정도 삭제 (선택사항)
      // 이 부분은 보안상 신중하게 처리해야 합니다.
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email 관리자 신청이 거부되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('거부 실패: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class DeviceApprovalStatusPage extends StatelessWidget {
  const DeviceApprovalStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기기별 승인 현황'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('devices').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류: \\${snapshot.error}'));
          }
          final devices = snapshot.data?.docs ?? [];
          if (devices.isEmpty) {
            return const Center(child: Text('등록된 기기가 없습니다.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final data = devices[index].data() as Map<String, dynamic>?;
              final deviceId = data?['deviceId'] ?? devices[index].id;
              final deviceName = data?['deviceName'] ?? '';
              final ownerEmail = data?['ownerEmail'] ?? '';
              final createdAt = data?['createdAt'];
              final lastActiveAt = data?['lastActiveAt'];
              final nickname = data?['nickname'] ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.verified_user, color: Colors.blue, size: 32),
                  title: Text('ID: $deviceId'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('기기명: $deviceName'),
                      Text('소유자: ${ownerEmail.isNotEmpty ? ownerEmail : '미지정'}'),
                      if (nickname.isNotEmpty) Text('별명: $nickname'),
                      if (createdAt != null) Text('생성일: \\${createdAt is Timestamp ? createdAt.toDate() : createdAt}'),
                      if (lastActiveAt != null) Text('마지막 활동: \\${lastActiveAt is Timestamp ? lastActiveAt.toDate() : lastActiveAt}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
