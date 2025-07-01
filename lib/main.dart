import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:bip32/bip32.dart' as bip32;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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

  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  String _transactionStatus = "";

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    EthereumAddress? address = await _wallet.getWalletAddress();
    String? seedPhrase = await _wallet.getSeedPhrase();
    setState(() {
      _walletAddress = address?.hex ?? 'No wallet found.';
      _seedPhrase = seedPhrase ?? '';
    });
  }

  Future<void> _createWallet() async {
    var result = await _wallet.createWallet();
    setState(() {
      _walletAddress = result['address'] ?? '';
      _seedPhrase = result['seedPhrase'] ?? '';
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

  Future<void> _sendTransaction() async {
    final String recipient = _recipientController.text;
    final String amountStr = _amountController.text;
    if (recipient.isEmpty || amountStr.isEmpty) {
      setState(() {
        _transactionStatus = 'Recipient and amount are required.';
      });
      return;
    }

    final BigInt amount =
        BigInt.from(double.parse(amountStr) * 1e18); // Convert ETH to wei
    setState(() {
      _transactionStatus = 'Signing transaction...';
    });

    try {
      await _wallet.sendSignedTransaction(recipient, amount, 31337);
      setState(() {
        _transactionStatus = 'Transaction sent successfully.';
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Ethereum Wallet Address:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SelectableText(_walletAddress,
                style: const TextStyle(fontSize: 16, color: Colors.blue),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_seedPhrase.isNotEmpty) ...[
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
              const SizedBox(height: 20),
            ],
            TextField(
              controller: _recipientController,
              decoration: const InputDecoration(
                  labelText: "Recipient Address", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: "Amount in ETH", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _sendTransaction,
              child: const Text("Send Transaction"),
            ),
            const SizedBox(height: 10),
            Text(_transactionStatus,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
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
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  final Web3Client client;
  final String apiUrl = "http://localhost:3000/sendTransaction";

  EthereumWallet() : client = Web3Client('http://127.0.0.1:8545', Client());

  Future<String> signTransaction(
      String recipient, BigInt amount, int chainId) async {
    final storage = FlutterSecureStorage();
    String? privateKeyHex = await storage.read(key: 'private_key');
    if (privateKeyHex == null) {
      throw Exception('No private key found.');
    }

    final EthPrivateKey credentials = EthPrivateKey.fromHex(privateKeyHex);

    final transaction = Transaction(
      to: EthereumAddress.fromHex(recipient),
      value: EtherAmount.fromBigInt(EtherUnit.wei, amount),
    );

    // Sign the transaction
    final signedTx = await client.signTransaction(credentials, transaction,
        chainId: chainId);

    print('Signed transaction: ${bytesToHex(signedTx)}');

    return bytesToHex(signedTx);
  }

  Future<void> sendSignedTransaction(
      String recipient, BigInt amount, int chainId) async {
    String signedTx = await signTransaction(recipient, amount, chainId);

    // Send the signed transaction to the server
    final response = await post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'signedTransaction': signedTx,
      }),
    );

    if (response.statusCode == 200) {
      print('Transaction sent successfully: ${response.body}');
    } else {
      print('Failed to send transaction: ${response.body}');
    }
  }

  Future<Map<String, String>> createWallet() async {
    // Generate a 12-word mnemonic phrase (128-bit entropy)
    final mnemonic = Mnemonic.generate(Language.english, entropyLength: 128);
    final seedPhrase = mnemonic.sentence;
    
    // Generate seed from mnemonic
    final seed = mnemonic.seed;
    
    // Use BIP32 to create master key from seed
    final masterKey = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
    
    // Derive Ethereum key using BIP44 path: m/44'/60'/0'/0/0
    // This matches MetaMask's derivation path
    final derivedKey = masterKey
        .derivePath("m/44'/60'/0'/0/0");
    
    // Use the derived private key
    final privateKeyBytes = derivedKey.privateKey!;
    final privateKey = EthPrivateKey(privateKeyBytes);
    
    final String privateKeyHex = privateKey.privateKeyInt.toRadixString(16);
    final EthereumAddress address = privateKey.address;

    // Store both the private key and seed phrase securely
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

  Future<Map<String, String>> importWallet(String seedPhrase) async {
    // Validate the seed phrase format and word count
    final words = seedPhrase.trim().split(' ');
    if (words.length != 12 && words.length != 24) {
      throw Exception('Seed phrase must be 12 or 24 words');
    }
    
    // Validate the seed phrase using BIP39
    final mnemonic = Mnemonic.fromSentence(seedPhrase.trim(), Language.english);
    
    // Generate seed from mnemonic
    final seed = mnemonic.seed;
    
    // Use BIP32 to create master key from seed
    final masterKey = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
    
    // Derive Ethereum key using BIP44 path: m/44'/60'/0'/0/0
    final derivedKey = masterKey.derivePath("m/44'/60'/0'/0/0");
    
    // Use the derived private key
    final privateKeyBytes = derivedKey.privateKey!;
    final privateKey = EthPrivateKey(privateKeyBytes);
    
    final String privateKeyHex = privateKey.privateKeyInt.toRadixString(16);
    final EthereumAddress address = privateKey.address;

    // Store both the private key and seed phrase securely
    await _storage.write(key: 'private_key', value: privateKeyHex);
    await _storage.write(key: 'seed_phrase', value: seedPhrase.trim());

    return {
      'address': address.hex,
      'seedPhrase': seedPhrase.trim(),
    };
  }
}
