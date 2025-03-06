import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Ethereum Wallet Address:',
            ),
            Padding(
                padding: const EdgeInsets.all(10.0),
                child: SelectableText(
                  _walletAddress,
                  style: const TextStyle(fontSize: 16, color: Colors.blue),
                  textAlign: TextAlign.center,
                ))
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
