// Minimal MetaTx Service for Gasless Transactions
// ERC-2771 Meta-Transaction Implementation for VersaForwarder

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';

/// Represents a forward request for ERC-2771 meta-transactions
class ForwardRequest {
  final String from;
  final String to;
  final String value;
  final String gas;
  final String nonce;
  final String deadline;
  final String data;

  ForwardRequest({
    required this.from,
    required this.to,
    required this.value,
    required this.gas,
    required this.nonce,
    required this.deadline,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'value': value,
        'gas': gas,
        'nonce': nonce,
        'deadline': deadline,
        'data': data,
      };
}

/// Simple EIP-712 signer without external dependencies
/// Implements EIP-712 structured data signing for VersaForwarder
class SimpleEIP712Signer {
  final int chainId;
  final String verifyingContract;

  SimpleEIP712Signer({required this.chainId, required this.verifyingContract});

  /// Sign a ForwardRequest using EIP-712 standard
  Future<String> sign(ForwardRequest req, EthPrivateKey key) async {
    // CRITICAL: Verify the private key matches the 'from' address
    final keyAddress = key.address.hex.toLowerCase();
    final fromAddress = req.from.toLowerCase();

    print('DEBUG: Private Key Address Check:');
    print('  Key derives to:  $keyAddress');
    print('  Request from:    $fromAddress');
    print(
        '  Match: ${keyAddress == fromAddress ? "✅ YES" : "❌ NO - THIS IS THE BUG!"}');
    print('');

    if (keyAddress != fromAddress) {
      throw Exception('CRITICAL BUG: Private key address mismatch!\n'
          'The private key derives to: $keyAddress\n'
          'But the from address is:    $fromAddress\n'
          'These must match for the signature to be valid!');
    }

    // Build EIP-712 Domain Separator
    final domainType = keccak256(Uint8List.fromList(utf8.encode(
        'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')));
    final nameHash =
        keccak256(Uint8List.fromList(utf8.encode('VersaForwarder')));
    final versionHash = keccak256(Uint8List.fromList(utf8.encode('1')));

    final domainSep = keccak256(Uint8List.fromList([
      ...domainType,
      ...nameHash,
      ...versionHash,
      ..._uint256(BigInt.from(chainId)),
      ..._address(verifyingContract),
    ]));

    // Build ForwardRequest Type Hash
    final reqType = keccak256(Uint8List.fromList(utf8.encode(
        'ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)')));
    final dataHash = keccak256(hexToBytes(req.data.substring(2)));

    // Build struct hash
    final structHash = keccak256(Uint8List.fromList([
      ...reqType,
      ..._address(req.from),
      ..._address(req.to),
      ..._uint256(BigInt.parse(req.value)),
      ..._uint256(BigInt.parse(req.gas)),
      ..._uint256(BigInt.parse(req.nonce)),
      ..._uint256(BigInt.parse(req.deadline)),
      ...dataHash,
    ]));

    // Build final digest: "\x19\x01" + domainSeparator + structHash
    final digest = keccak256(
        Uint8List.fromList([0x19, 0x01, ...domainSep, ...structHash]));

    // Debug logging
    print('DEBUG EIP-712 Hashes:');
    print('  Domain Separator: ${bytesToHex(domainSep, include0x: true)}');
    print('  Struct Hash: ${bytesToHex(structHash, include0x: true)}');
    print('  Final Digest: ${bytesToHex(digest, include0x: true)}');

    // Sign the digest using raw ECDSA (no additional hashing!)
    // web3dart's signToEcSignature() hashes the input with keccak256,
    // but our digest is already the final hash. We need raw ECDSA signing.
    final signature = _signRawEcdsa(digest, key);

    final sigHex = bytesToHex(signature, include0x: true);
    print('  Full signature: $sigHex');

    return sigHex;
  }

  /// Convert uint256 to 32-byte array
  Uint8List _uint256(BigInt v) {
    final b = Uint8List(32);
    final h = v.toRadixString(16).padLeft(64, '0');
    b.setAll(0, hexToBytes(h));
    return b;
  }

  /// Convert address to 32-byte array (left-padded)
  Uint8List _address(String addr) {
    final b = Uint8List(32);
    b.setAll(12, hexToBytes(addr.substring(2)));
    return b;
  }

  /// Sign a digest with raw ECDSA (no additional hashing)
  /// This is required for EIP-712 signatures where the digest is already computed
  Uint8List _signRawEcdsa(Uint8List digest, EthPrivateKey privateKey) {
    // Get the secp256k1 curve parameters
    final ECDomainParameters params = ECCurve_secp256k1();

    // Create private key from BigInt
    final privateKeyInt = privateKey.privateKeyInt;
    final privateKeyParams = ECPrivateKey(privateKeyInt, params);

    // Create ECDSA signer with deterministic k (RFC 6979)
    final signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    final privParams = PrivateKeyParameter(privateKeyParams);
    signer.init(true, privParams);

    // Sign the digest (no hashing - digest is already the final hash!)
    final ECSignature ecSig = signer.generateSignature(digest) as ECSignature;

    // Get r and s
    BigInt r = ecSig.r;
    BigInt s = ecSig.s;

    // Ensure s is in the lower half (BIP-62)
    final ECCurve_secp256k1 curve = params as ECCurve_secp256k1;
    final halfCurveOrder = curve.n >> 1;
    if (s.compareTo(halfCurveOrder) > 0) {
      s = curve.n - s;
    }

    // Calculate recovery ID (v)
    // We need to find which of the 4 possible public keys matches our address
    final targetAddress = privateKey.address.addressBytes;

    int recoveryId = -1;
    for (int i = 0; i < 4; i++) {
      try {
        final recovered = _recoverPublicKey(digest, r, s, i, params);
        if (recovered != null) {
          // Derive address from public key
          final publicKeyBytes =
              recovered.Q!.getEncoded(false).sublist(1); // Remove 0x04 prefix
          final addressBytes =
              keccak256(publicKeyBytes).sublist(12); // Last 20 bytes

          if (_bytesEqual(addressBytes, targetAddress)) {
            recoveryId = i;
            break;
          }
        }
      } catch (e) {
        continue;
      }
    }

    if (recoveryId == -1) {
      throw Exception('Failed to calculate recovery ID');
    }

    // v = 27 + recovery_id (Ethereum uses 27/28 for non-EIP-155 signatures)
    final v = 27 + recoveryId;

    print('  Signature r: 0x${r.toRadixString(16).padLeft(64, '0')}');
    print('  Signature s: 0x${s.toRadixString(16).padLeft(64, '0')}');
    print('  Signature v: $v');

    // Construct 65-byte signature: r (32) + s (32) + v (1)
    final signature = Uint8List(65);
    signature.setAll(0, _uint256(r));
    signature.setAll(32, _uint256(s));
    signature[64] = v;

    return signature;
  }

  /// Recover public key from signature (for finding recovery ID)
  ECPublicKey? _recoverPublicKey(
    Uint8List digest,
    BigInt r,
    BigInt s,
    int recoveryId,
    ECDomainParameters params,
  ) {
    final n = params.n;
    final i = BigInt.from(recoveryId ~/ 2);
    final x = r + (i * n);

    // Use the field prime (p) from the curve
    final prime = params.curve.fieldSize;
    // A simple way to check bounds without the BigInt? null issue:
    if (x.compareTo(params.n) >= 0) return null;

    try {
      final R = _decompressKey(x, (recoveryId & 1) == 1, params.curve);
      if (R == null) return null;

      final e = _bytesToBigInt(digest);
      final eInv = (BigInt.zero - e) % n;
      final rInv = r.modInverse(n);
      final srInv = (rInv * s) % n;
      final eInvrInv = (rInv * eInv) % n;

      final q = (params.G * eInvrInv)! + (R * srInv)!;
      return ECPublicKey(q, params);
    } catch (e) {
      return null;
    }
  }

  /// Decompress elliptic curve point
  ECPoint? _decompressKey(BigInt xBN, bool yBit, ECCurve c) {
    final compEnc = _x9IntegerToBytes(xBN, 1 + ((c.fieldSize + 7) ~/ 8));
    compEnc[0] = yBit ? 0x03 : 0x02;
    return c.decodePoint(compEnc);
  }

  Uint8List _x9IntegerToBytes(BigInt s, int qLength) {
    final bytes = _bigIntToBytes(s);

    if (qLength < bytes.length) {
      return bytes.sublist(0, bytes.length - qLength);
    } else if (qLength > bytes.length) {
      final tmp = Uint8List(qLength);
      tmp.setAll(qLength - bytes.length, bytes);
      return tmp;
    }

    return bytes;
  }

  Uint8List _bigIntToBytes(BigInt number) {
    final bytes = <int>[];
    var num = number;
    while (num > BigInt.zero) {
      bytes.insert(0, (num & BigInt.from(0xff)).toInt());
      num = num >> 8;
    }
    return Uint8List.fromList(bytes.isEmpty ? [0] : bytes);
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Minimal MetaTransaction Service for Gasless Transactions
class MetaTxService {
  final String relayerUrl;
  final String forwarderAddress;
  final int chainId;

  MetaTxService({
    required this.relayerUrl,
    required this.forwarderAddress,
    required this.chainId,
  });

  /// Get current nonce for an address from the relayer
  Future<String> getNonce(String address) async {
    print('Fetching nonce for $address from $relayerUrl/nonce/$address');
    final res = await http.get(Uri.parse('$relayerUrl/nonce/$address'));

    print('Nonce response: ${res.statusCode} - ${res.body}');
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['nonce'].toString();
    }
    throw Exception('Failed to fetch nonce: ${res.body}');
  }

  /// Sign an ERC20 token transfer as a meta-transaction
  Future<Map<String, dynamic>> signTokenTransfer({
    required EthPrivateKey privateKey,
    required String tokenAddress,
    required String from,
    required String to,
    required BigInt amount,
  }) async {
    print('\n=== Signing Token Transfer ===');
    print('Token: $tokenAddress');
    print('From: $from → To: $to');
    print('Amount: $amount');

    final nonce = await getNonce(from);
    print('Nonce: $nonce');

    final data = _encodeTransfer(to, amount);
    print('Encoded data: $data');

    final deadline = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
    final req = ForwardRequest(
      from: from,
      to: tokenAddress,
      value: '0',
      gas: '200000',
      nonce: nonce,
      deadline: deadline.toString(),
      data: data,
    );

    final signer = SimpleEIP712Signer(
        chainId: chainId, verifyingContract: forwarderAddress);
    final sig = await signer.sign(req, privateKey);

    print('Signature: $sig');
    print('=== Signing Complete ===\n');

    return {'request': req.toJson(), 'signature': sig};
  }

  /// Relay a signed transaction to the relayer service
  Future<Map<String, dynamic>> relayTransaction(
      Map<String, dynamic> signedTx) async {
    print('\n=== Relaying Transaction ===');
    print('URL: $relayerUrl/relay');
    print('Payload: ${jsonEncode(signedTx)}');

    final res = await http.post(
      Uri.parse('$relayerUrl/relay'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(signedTx),
    );

    print('Response status: ${res.statusCode}');
    print('Response body: ${res.body}');

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        print('=== Relay Success ===\n');
        return {
          'success': true,
          'txHash': data['txHash'],
          'message': data['message'] ?? 'Success'
        };
      }
    }
    throw Exception('Relay failed: ${res.body}');
  }

  /// Verify signature without executing (dry run)
  Future<bool> verifySignature(Map<String, dynamic> signedTx) async {
    print('Verifying signature at $relayerUrl/verify');
    final res = await http.post(
      Uri.parse('$relayerUrl/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(signedTx),
    );

    print('Verify response: ${res.statusCode} - ${res.body}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['success'] == true;
    }
    return false;
  }

  /// Encode ERC20 transfer(address,uint256) function call
  String _encodeTransfer(String to, BigInt amount) {
    // Function selector: keccak256("transfer(address,uint256)")[0:4]
    final selector = 'a9059cbb';
    final recipient = Uint8List(32);
    recipient.setRange(12, 32, EthereumAddress.fromHex(to).addressBytes);

    final amountBytes = Uint8List(32);
    amountBytes.setAll(
        0, hexToBytes(amount.toRadixString(16).padLeft(64, '0')));

    return '0x${bytesToHex(Uint8List.fromList([
          ...hexToBytes(selector),
          ...recipient,
          ...amountBytes
        ]))}';
  }
}
