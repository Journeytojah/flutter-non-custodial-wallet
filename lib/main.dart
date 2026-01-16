import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/meta_tx_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ethereum Wallet Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Ethereum Wallet'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final EthereumWallet _wallet = EthereumWallet();
  String _walletAddress = 'No wallet yet.';
  String _seedPhrase = '';
  bool _hasWallet = false;

  bool _useGasless = false;
  final TextEditingController _forwarderController = TextEditingController();
  final TextEditingController _relayerController = TextEditingController();

  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _tokenAddressController = TextEditingController();
  final TextEditingController _jwtTokenController = TextEditingController();
  String _transactionStatus = "";
  bool _isTokenTransfer = false; // Toggle between native and token transfer

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _clearDataOnFreshInstall();
    await _loadWallet();
    await _loadJwtToken();

    // Load gasless config
    final forwarder = await _wallet.getForwarder();
    final relayerUrl = await _wallet.getRelayerUrl();
    setState(() {
      _forwarderController.text = forwarder;
      _relayerController.text = relayerUrl;
    });
  }

  Future<void> _clearDataOnFreshInstall() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRunBefore = prefs.getBool('has_run_before') ?? false;

    if (!hasRunBefore) {
      await _wallet.clearWallet();
      await prefs.setBool('has_run_before', true);
    }
  }

  Future<void> _loadWallet() async {
    EthereumAddress? address = await _wallet.getWalletAddress();
    String? seedPhrase = await _wallet.getSeedPhrase();
    setState(() {
      if (address != null && seedPhrase != null) {
        _walletAddress = address.hex;
        _seedPhrase = seedPhrase;
        _hasWallet = true;
      } else {
        _walletAddress = 'No wallet yet.';
        _seedPhrase = '';
        _hasWallet = false;
      }
    });
  }

  Future<void> _loadJwtToken() async {
    String? token = await _wallet.getJwtToken();
    if (token != null) {
      _jwtTokenController.text = token;
    }
  }

  Future<void> _createWallet() async {
    await _wallet.clearWallet();
    var result = await _wallet.createWallet();
    setState(() {
      _walletAddress = result['address'] ?? '';
      _seedPhrase = result['seedPhrase'] ?? '';
      _hasWallet = true;
    });
  }

  Future<void> _importWallet() async {
    String? seedPhrase = await _showImportDialog();
    if (seedPhrase != null && seedPhrase.isNotEmpty) {
      try {
        var result = await _wallet.importWallet(seedPhrase);
        setState(() {
          _walletAddress = result['address'] ?? '';
          _seedPhrase = result['seedPhrase'] ?? '';
          _hasWallet = true;
          _transactionStatus = 'Wallet imported successfully!';
        });
      } catch (e) {
        setState(() {
          _transactionStatus = 'Failed to import wallet: ${e.toString()}';
        });
      }
    }
  }

  Future<String?> _showImportDialog() async {
    TextEditingController importController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Import Wallet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your 12-word seed phrase:'),
              const SizedBox(height: 16),
              TextField(
                controller: importController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'word1 word2 word3 ...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Import'),
              onPressed: () {
                Navigator.of(context).pop(importController.text.trim());
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveJwtToken() async {
    final token = _jwtTokenController.text.trim();
    if (token.isNotEmpty) {
      await _wallet.saveJwtToken(token);
      setState(() {
        _transactionStatus = 'JWT Token saved successfully!';
      });
    } else {
      setState(() {
        _transactionStatus = 'Please enter a valid JWT token';
      });
    }
  }

  Future<void> _sendTransaction() async {
    final String recipient = _recipientController.text;
    final String amountStr = _amountController.text;

    if (recipient.isEmpty || amountStr.isEmpty) {
      setState(() {
        _transactionStatus = 'Recipient and amount are required.';
      });
      return;
    }

    if (_isTokenTransfer && _tokenAddressController.text.isEmpty) {
      setState(() {
        _transactionStatus = 'Token address is required for token transfers.';
      });
      return;
    }

    // JWT token only required for non-gasless transactions
    if (!_useGasless) {
      String? token = await _wallet.getJwtToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _transactionStatus = 'Please set JWT token first.';
        });
        return;
      }
    }

    final BigInt amount = BigInt.from(double.parse(amountStr) * 1e18);
    setState(() {
      _transactionStatus = _useGasless
          ? 'Signing gasless transaction...'
          : 'Signing transaction...';
    });

    try {
      if (_useGasless) {
        // GASLESS PATH
        if (_isTokenTransfer) {
          final txHash = await _wallet.sendGaslessTokenTransfer(
            _tokenAddressController.text,
            recipient,
            amount,
          );
          setState(() {
            _transactionStatus = 'Gasless TX sent!\nHash: $txHash';
          });
        } else {
          setState(() {
            _transactionStatus = 'Native gasless not implemented yet';
          });
        }
      } else if (_isTokenTransfer) {
        // ERC20 Token Transfer
        await _wallet.sendSignedTokenTransaction(
          _tokenAddressController.text,
          recipient,
          amount,
          3502, // JFIN Testnet
        );
      } else {
        // Native Token Transfer
        await _wallet.sendSignedTransaction(
          recipient,
          amount,
          3502, // JFIN Testnet
        );
      }
      setState(() {
        _transactionStatus = 'Transaction sent successfully!';
      });
    } catch (e) {
      setState(() {
        _transactionStatus = 'Failed to send transaction: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!_hasWallet) ...[
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              const Text('No Wallet Found',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 10),
              const Text(
                  'Create a new wallet or import an existing one to get started.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
            ] else ...[
              const Text('Ethereum Wallet Address:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SelectableText(_walletAddress,
                  style: const TextStyle(fontSize: 16, color: Colors.blue),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              const Text('Seed Phrase:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: SelectableText(_seedPhrase,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const SizedBox(height: 20),
              const Text('JWT Token (Required for API):',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(
                controller: _jwtTokenController,
                decoration: const InputDecoration(
                    labelText: "JWT Token",
                    border: OutlineInputBorder(),
                    hintText: "Paste your JWT token here"),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _saveJwtToken,
                child: const Text("Save JWT Token"),
              ),
              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const SizedBox(height: 20),
              const Text('Send Transaction:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // Toggle between native and token transfer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Native Token'),
                  Switch(
                    value: _isTokenTransfer,
                    onChanged: (value) {
                      setState(() {
                        _isTokenTransfer = value;
                      });
                    },
                  ),
                  const Text('ERC20 Token'),
                ],
              ),
              const SizedBox(height: 10),

              const Divider(thickness: 2),
              const SizedBox(height: 20),
              const Text('Gasless Config:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(
                controller: _forwarderController,
                decoration: const InputDecoration(
                    labelText: "Forwarder", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _relayerController,
                decoration: const InputDecoration(
                    labelText: "Relayer URL", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await _wallet.saveGaslessConfig(
                      _forwarderController.text, _relayerController.text);
                  setState(() => _transactionStatus = 'Config saved!');
                },
                child: const Text("Save Config"),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Regular'),
                  Switch(
                      value: _useGasless,
                      onChanged: (v) => setState(() => _useGasless = v)),
                  const Text('Gasless'),
                ],
              ),

              // Show token address field only for token transfers
              if (_isTokenTransfer) ...[
                TextField(
                  controller: _tokenAddressController,
                  decoration: const InputDecoration(
                      labelText: "Token Contract Address",
                      border: OutlineInputBorder(),
                      hintText: "0x..."),
                ),
                const SizedBox(height: 10),
              ],

              TextField(
                controller: _recipientController,
                decoration: const InputDecoration(
                    labelText: "Recipient Address",
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: _isTokenTransfer
                        ? "Amount in Tokens"
                        : "Amount in JFIN",
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _sendTransaction,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: Text(
                  _isTokenTransfer
                      ? "Send Token Transfer"
                      : "Send Native Transfer",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_transactionStatus.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _transactionStatus.contains('success')
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _transactionStatus.contains('success')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Text(_transactionStatus,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _transactionStatus.contains('success')
                            ? Colors.green[900]
                            : Colors.red[900]),
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _importWallet,
            tooltip: 'Import Wallet',
            heroTag: 'import',
            child: const Icon(Icons.file_download),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _createWallet,
            tooltip: 'Create Wallet',
            heroTag: 'create',
            child: const Icon(Icons.account_balance_wallet),
          ),
        ],
      ),
    );
  }
}

class EthereumWallet {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final Web3Client client;

  final String baseUrl;

  String? _forwarderAddress;
  String? _relayerUrl;

  EthereumWallet({
    this.baseUrl = "http://localhost:50002",
  }) : client = Web3Client('http://127.0.0.1:8545', Client());

  String get apiUrl => "$baseUrl/v1/customers/wallets/transactions";

  Future<void> saveGaslessConfig(String forwarder, String relayer) async {
    await _storage.write(key: 'forwarder_address', value: forwarder);
    await _storage.write(key: 'relayer_url', value: relayer);
    _forwarderAddress = forwarder;
    _relayerUrl = relayer;
  }

  Future<String> sendGaslessTokenTransfer(
    String tokenAddress,
    String recipient,
    BigInt amount,
  ) async {
    String? privateKeyHex = await _storage.read(key: 'private_key');
    if (privateKeyHex == null) throw Exception('No private key found');

    final credentials = EthPrivateKey.fromHex(privateKeyHex);
    final from = credentials.address.hex;

    final metaTx = MetaTxService(
      relayerUrl: await getRelayerUrl(),
      forwarderAddress: await getForwarder(),
      chainId: 31337, // Hardhat
    );

    final signedTx = await metaTx.signTokenTransfer(
      privateKey: credentials,
      tokenAddress: tokenAddress,
      from: from,
      to: recipient,
      amount: amount,
    );

    final result = await metaTx.relayTransaction(signedTx);
    return result['txHash'];
  }

  Future<String> getForwarder() async {
    _forwarderAddress ??= await _storage.read(key: 'forwarder_address');
    return _forwarderAddress ?? '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  }

  Future<String> getRelayerUrl() async {
    _relayerUrl ??= await _storage.read(key: 'relayer_url');
    return _relayerUrl ?? 'http://localhost:3000/api';
  }

  Future<void> saveJwtToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<String?> getJwtToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  // Sign native token transfer
  Future<String> signTransaction(
      String recipient, BigInt amount, int chainId) async {
    String? privateKeyHex = await _storage.read(key: 'private_key');
    if (privateKeyHex == null) {
      throw Exception('No private key found.');
    }

    final EthPrivateKey credentials = EthPrivateKey.fromHex(privateKeyHex);

    final transaction = Transaction(
      to: EthereumAddress.fromHex(recipient),
      value: EtherAmount.fromBigInt(EtherUnit.wei, amount),
    );

    final signedTx = await client.signTransaction(credentials, transaction,
        chainId: chainId);

    print('Signed transaction: ${bytesToHex(signedTx)}');

    return bytesToHex(signedTx);
  }

  // Sign ERC20 token transfer
  Future<String> signTokenTransaction(
      String tokenAddress, String recipient, BigInt amount, int chainId) async {
    String? privateKeyHex = await _storage.read(key: 'private_key');
    if (privateKeyHex == null) {
      throw Exception('No private key found.');
    }

    final EthPrivateKey credentials = EthPrivateKey.fromHex(privateKeyHex);

    // ERC20 transfer function signature: transfer(address,uint256)
    // Function selector: 0xa9059cbb
    final transferFunctionSelector = hexToBytes('a9059cbb');

    // Encode recipient address (32 bytes, padded)
    final recipientAddress = EthereumAddress.fromHex(recipient);
    final recipientBytes = recipientAddress.addressBytes;
    final paddedRecipient = Uint8List(32);
    paddedRecipient.setRange(12, 32, recipientBytes); // Pad left with zeros

    // Encode amount (32 bytes, big-endian)
    final amountBytes = Uint8List(32);
    final amountHex = amount.toRadixString(16).padLeft(64, '0');
    final amountBytesList = hexToBytes(amountHex);
    amountBytes.setAll(0, amountBytesList);

    // Combine: function selector + recipient + amount
    final data = Uint8List.fromList([
      ...transferFunctionSelector,
      ...paddedRecipient,
      ...amountBytes,
    ]);

    print('Token transfer data: ${bytesToHex(data)}');

    final transaction = Transaction(
      to: EthereumAddress.fromHex(tokenAddress),
      value: EtherAmount.zero(), // No native token sent, only ERC20
      data: data,
    );

    final signedTx = await client.signTransaction(credentials, transaction,
        chainId: chainId);

    print('Signed token transaction: ${bytesToHex(signedTx)}');

    return bytesToHex(signedTx);
  }

  // Send native token transaction
  Future<void> sendSignedTransaction(
      String recipient, BigInt amount, int chainId) async {
    String signedTx = await signTransaction(recipient, amount, chainId);
    await _sendToApi(signedTx);
  }

  // Send ERC20 token transaction
  Future<void> sendSignedTokenTransaction(
      String tokenAddress, String recipient, BigInt amount, int chainId) async {
    String signedTx =
        await signTokenTransaction(tokenAddress, recipient, amount, chainId);
    await _sendToApi(signedTx);
  }

  // Common method to send signed transaction to API
  Future<void> _sendToApi(String signedTx) async {
    if (!signedTx.startsWith('0x')) {
      signedTx = '0x$signedTx';
    }

    String? token = await getJwtToken();
    if (token == null || token.isEmpty) {
      throw Exception('JWT token is required. Please set it first.');
    }

    print('Sending transaction to API: $apiUrl');
    print('Signed transaction hex: $signedTx');

    final response = await post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'signedTxHex': signedTx,
      }),
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final data = responseData['data'];
      print('Transaction sent successfully!');
      print('Transaction Hash: ${data['txHash']}');
      print('Explorer URL: ${data['explorerUrl']}');
      print('Status: ${data['status']}');
    } else {
      print('Failed to send transaction: ${response.body}');
      throw Exception('Failed to send transaction: ${response.body}');
    }
  }

  Future<Map<String, String>> createWallet() async {
    final mnemonic = Mnemonic.generate(Language.english, entropyLength: 128);
    final seedPhrase = mnemonic.sentence;
    final seed = mnemonic.seed;
    final masterKey = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
    final derivedKey = masterKey.derivePath("m/44'/60'/0'/0/0");
    final privateKeyBytes = derivedKey.privateKey!;
    final privateKey = EthPrivateKey(privateKeyBytes);
    final String privateKeyHex = privateKey.privateKeyInt.toRadixString(16);
    final EthereumAddress address = privateKey.address;

    await _storage.write(key: 'private_key', value: privateKeyHex);
    await _storage.write(key: 'seed_phrase', value: seedPhrase);

    return {
      'address': address.hex,
      'seedPhrase': seedPhrase,
    };
  }

  Future<EthereumAddress?> getWalletAddress() async {
    String? privateKeyHex = await _storage.read(key: 'private_key');
    if (privateKeyHex == null) {
      return null;
    }

    final EthPrivateKey privateKey = EthPrivateKey.fromHex(privateKeyHex);
    return privateKey.address;
  }

  Future<String?> getSeedPhrase() async {
    return await _storage.read(key: 'seed_phrase');
  }

  Future<void> clearWallet() async {
    await _storage.delete(key: 'private_key');
    await _storage.delete(key: 'seed_phrase');
  }

  Future<Map<String, String>> importWallet(String seedPhrase) async {
    final words = seedPhrase.trim().split(' ');
    if (words.length != 12 && words.length != 24) {
      throw Exception('Seed phrase must be 12 or 24 words');
    }

    final mnemonic = Mnemonic.fromSentence(seedPhrase.trim(), Language.english);
    final seed = mnemonic.seed;
    final masterKey = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
    final derivedKey = masterKey.derivePath("m/44'/60'/0'/0/0");
    final privateKeyBytes = derivedKey.privateKey!;
    final privateKey = EthPrivateKey(privateKeyBytes);
    final String privateKeyHex = privateKey.privateKeyInt.toRadixString(16);
    final EthereumAddress address = privateKey.address;

    await _storage.write(key: 'private_key', value: privateKeyHex);
    await _storage.write(key: 'seed_phrase', value: seedPhrase.trim());

    return {
      'address': address.hex,
      'seedPhrase': seedPhrase.trim(),
    };
  }
}
