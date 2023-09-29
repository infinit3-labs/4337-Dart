library pks_4337_sdk;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pks_4337_sdk/pks_4337_sdk.dart';
import 'package:pks_4337_sdk/src/4337/chains.dart';
import 'package:pks_4337_sdk/src/4337/modules/contract.dart';
import 'package:pks_4337_sdk/src/abi/accountFactory.g.dart';
import 'package:pks_4337_sdk/src/abi/entrypoint.g.dart';
import "package:web3dart/web3dart.dart";

class Wallet extends Signer {
  final Web3Client walletClient;
  final BundlerProvider walletProvider;
  final IChain walletChain;

  late final Entrypoint entrypoint;
  bool _deployed = false;

  EthereumAddress _walletAddress;
  Address get address => Address.fromEthAddress(_walletAddress);
  String toHex() => _walletAddress.hexEip55;

  /// [Entrypoint] is not initialized
  /// you have to call Wallet.init() instead
  ///
  /// instantiate [Wallet] directly when you have the [address] of the account,
  /// and do not need to interact with the entrypoint.
  /// effective during recovery.
  Wallet(
      {required IChain chain,
      super.hdkey,
      super.passkey,
      super.signer,
      EthereumAddress? address})
      : walletChain = chain.validate(),
        walletProvider = BundlerProvider(chain.chainId, chain.bundlerUrl!),
        walletClient = Web3Client(chain.rpcUrl!, http.Client()),
        _walletAddress = address ?? Chains.zeroAddress;

  /// creates a [Wallet] instance, additionally initializes the [Entrypoint] contract
  /// call [init] when you have to [wait] for userOp's or need to use entrypoint specific methods
  /// effective during initial wallet creation
  static Wallet init(IChain chain,
      {HDkeysInterface? hdkey,
      PasskeysInterface? passkey,
      SignerType signer = SignerType.hdkeys,
      EthereumAddress? address}) {
    final instance = Wallet(
        chain: chain,
        hdkey: hdkey,
        passkey: passkey,
        signer: signer,
        address: address);
    instance.entrypoint = Entrypoint(
      address: chain.entrypoint,
      client: instance.walletClient,
    );
    return instance;
  }

  Future<EtherAmount> getBalance() async {
    return await walletClient.getBalance(_walletAddress);
  }

  Future<Uint256> getNonce({BigInt? key}) async {
    final nonce = await entrypoint.getNonce(_walletAddress, key ?? BigInt.zero);
    return Uint256(nonce);
  }

  Future<bool> _checkDeployment() async {
    bool isDeployed = await Contract(_provider).deployed(_walletAddress);
    isDeployed ? _deployed = true : _deployed = false;
    return isDeployed;
  }

  Future<EthereumAddress> _create(EthereumAddress owner, Uint256 salt) async {
    FactoryInterface factory = AccountFactory(
        address: Chains.accountFactory,
        client: walletClient,
        chainId: walletChain.chainId) as FactoryInterface;
    return await factory.getAddress(owner, salt.value);
  }

  /// does not deploy an account
  /// only generates an address based on the provided inputs
  /// give the same exact inputs, the same exact address will be generated.
  /// [deployed] will be called before sending any transaction
  /// if contract is yet to be deployed, an initCode will be attached on the first transaction.
  Future create(Uint256 salt, {int? account, String? accountId}) async {
    require(defaultSigner == SignerType.hdkeys,
        "Create: you need to set HD Keys as your default Signer");
    require(hdkey != null, "Create: HD Key instance is required!");
    EthereumAddress owner = EthereumAddress.fromHex(
        await hdkey!.getAddress(account ?? 0, id: accountId));
    _walletAddress = await _create(owner, salt);
  }

  Future<EthereumAddress> _createPasskeyAccount(
    FactoryInterface factory,
    Uint8List credentialHex,
    Uint256 x,
    Uint256 y,
    Uint256 salt,
  ) async {
    return await factory.getPasskeyAccountAddress(
        credentialHex, x.value, y.value, salt.value);
  }

  /// alternate account contract
  /// generates a smart Account address for secp256r1 signature accounts
  /// requires a p256 account factory contract.
  /// supports creating only p256 wallet by default.
  Future createPasskeyAccount(
      Uint8List credentialHex, Uint256 x, Uint256 y, Uint256 salt) async {
    require(defaultSigner == SignerType.passkeys,
        "Create P256: you need to set PassKeys as your default Signer");
    require(passkey != null, "Create P256: PassKey instance is required!");
    _walletAddress =
        await _createPasskeyAccount(factory, credentialHex, x, y, salt);
  }

  // UserOperation buildUserOp() {}

  Future signUserOperation() async {}
  Future sendSignedUserOperation() async {
    /// sends a custom built user operation via a smart wallet
  }
  Future signAndSendUserOperation() async {
    /// sends a custom built user operation via a smart wallet
  }

  Future<UserOperationResponse?> sendTransaction({
    required EthereumAddress to,
    required Uint256 value,
    required Uint8List payload,
    BundlerProvider? bundlerProvider,
  }) async {
    if (!(await _checkDeployment())) {}
    final nonce = await getNonce();
    UserOperation userOp = UserOperation(
      toHex(),
      nonce.value,
      '',
      '$payload',
      BigInt.tryParse('$value') ?? BigInt.from(0),
      BigInt.from(0),
      BigInt.from(0),
      BigInt.from(0),
      BigInt.from(0),
      '',
      '',
    );
    final signedOps = await sign(userOp);
    final response = await bundlerProvider?.sendUserOperation(
        signedOps, Chains.entrypoint as String);
    if (response?.userOpHash == null) {
      throw Exception('Error sending transaction');
    }

    return response;
  }

  Future sendBatchedTransaction() async {
    /// sends a batched transaction via a smart wallet
  }

  Future signTransaction() async {}

  Future send() async {
    /// transfers eth via a smart wallet
    /// token transfers will be handled from the wallet class modules
  }

  /// waits for a userOp to complete.
  /// Isolates this in a separate thread
  void wait(WaitIsolateMessage message) async {
    final block = await walletClient.getBlockNumber();
    final end = DateTime.now().millisecondsSinceEpoch + message.millisecond;

    while (DateTime.now().millisecondsSinceEpoch < end) {
      final filterEvent = await walletClient
          .events(
            FilterOptions.events(
              contract: entrypoint.self,
              event: entrypoint.self.event('UserOperationEvent'),
              fromBlock: BlockNum.exact(block - 100),
            ),
          )
          .take(1)
          .first;
      if (filterEvent.transactionHash != null) {
        Isolate.current.kill(priority: Isolate.immediate);
        message.sendPort.send(filterEvent);
        return;
      }
      await Future.delayed(Duration(milliseconds: message.millisecond));
    }

    Isolate.current.kill(priority: Isolate.immediate);
    message.sendPort.send(null);
  }
}

// Future userOptester() async {
//   final uop = UserOperation(
//     "0x3AcF7270a4e8D1d1b0656aA76E50C28a40446e77",
//     BigInt.from(2),
//     '0x',
//     '0xb61d27f60000000000000000000000003acf7270a4e8d1d1b0656aa76e50c28a40446e77000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004b0d691fe00000000000000000000000000000000000000000000000000000000',
//     BigInt.from(55000),
//     BigInt.from(80000),
//     BigInt.from(51000),
//     BigInt.zero,
//     BigInt.zero,
//     '0x065f98b3a6250d7a2ba16af1d9cd70e7399dfdd43a59b066fad919c0b0091d8a0ae13b9ee0dc11576f89fb86becac6febf1ea859cb5dad5f3aac3d024eb77f681c',
//     '0x',
//   ).toMap();

//   final etp = await walletProvider.getUserOpReceipt(
//       "0x968330a7d22692ee1214512ee474de65ff00d246440978de87e5740d09d2d354");
//   log("etp: ${etp.toString()}");
//   // walletProvider.sendUserOperation(et, entryPoint)
// }
