part of '../../variance_dart.dart';

/// A class that extends the Safe4337Module and implements the Safe4337ModuleBase interface.
/// It provides functionality related to Safe accounts and user operations on an Ethereum-like blockchain.
class _SafePlugin extends Safe4337Module implements Safe4337ModuleBase {
  /// Creates a new instance of the _SafePlugin class.
  ///
  /// [address] is the address of the Safe 4337 module.
  /// [chainId] is the ID of the blockchain chain.
  /// [client] is the client used for interacting with the blockchain.
  _SafePlugin({
    required super.address,
    super.chainId,
    required super.client,
  });

  /// Encodes the signature of a user operation with a validity period.
  ///
  /// [signature] is the signature of the user operation.
  /// [blockInfo] is the current blockInformation including the timestamp and baseFee.
  ///
  /// Returns a HexString representing the encoded signature with a validity period.
  String getSafeSignature(String signature, BlockInformation blockInfo) {
    final timestamp = blockInfo.timestamp.millisecondsSinceEpoch ~/ 1000;

    String validAfter = (timestamp - 3600).toRadixString(16);
    validAfter = '0' * (12 - validAfter.length) + validAfter;

    String validUntil = (timestamp + 3600).toRadixString(16);
    validUntil = '0' * (12 - validUntil.length) + validUntil;

    int v = int.parse(signature.substring(130, 132), radix: 16);

    if (v >= 27 && v <= 30) {
      v += 4;
    }

    String modifiedV = v.toRadixString(16);
    if (modifiedV.length == 1) {
      modifiedV = '0$modifiedV';
    }

    return '0x$validAfter$validUntil${signature.substring(2, 130)}$modifiedV';
  }

  /// Computes the hash of a Safe UserOperation.
  ///
  /// [op] is an object representing the user operation details.
  /// [blockInfo] is the current timestamp in seconds.
  ///
  /// Returns a Future that resolves to the hash of the user operation as a Uint8List.
  Future<Uint8List> getSafeOperationHash(
          UserOperation op, BlockInformation blockInfo) async =>
      getOperationHash([
        op.sender,
        op.nonce,
        op.initCode,
        op.callData,
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        op.paymasterAndData,
        hexToBytes(getSafeSignature(op.signature, blockInfo))
      ]);
}
