import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

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
    setState(() {
      _walletAddress = address?.hex ?? 'No wallet found.';
    });
  }

  Future<void> _createWallet() async {
    String address = await _wallet.createWallet();
    setState(() {
      _walletAddress = address;
    });
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
      floatingActionButton: FloatingActionButton(
        onPressed: _createWallet,
        tooltip: 'Create Wallet',
        child: const Icon(Icons.account_balance_wallet),
      ), // This trailing comma makes auto-formatting nicer for build methods.
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
      value: EtherAmount.fromUnitAndValue(EtherUnit.wei, amount),
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

  Future<String> createWallet() async {
    final rng = Random.secure();
    final EthPrivateKey privateKey = EthPrivateKey.createRandom(rng);

    final String privateKeyHex = privateKey.privateKeyInt.toRadixString(16);
    final EthereumAddress address = privateKey.address;

    // Store the private key securely
    await _storage.write(key: 'private_key', value: privateKeyHex);

    return address.hex;
  }

  Future<EthereumAddress?> getWalletAddress() async {
    String? privateKeyHex = await _storage.read(key: 'private_key');
    if (privateKeyHex == null) {
      return null;
    }

    final EthPrivateKey privateKey = EthPrivateKey.fromHex(privateKeyHex);
    return privateKey.address;
  }
}
