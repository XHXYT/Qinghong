import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/**
 * 密码加密工具：HUKS AES-256-GCM，硬件密钥（不可导出），
 * 数据库存 base64(nonce + 密文 + tag)，前缀 enc1:。
 * 数据库文件被拷走也无法解密（密钥在通用密钥库中，不出 TEE）。
 */

const KEY_ALIAS = 'qinghong_pwd_master_key_v1';
const AAD_TEXT = 'qinghong.password.v1';
const ENCRYPTED_PREFIX = 'enc1:';
const TAG_LEN = 16;
const NONCE_LEN = 12;

function utf8Bytes(text: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(text);
}

function utf8Text(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeWithStream(bytes);
}

function genProperties(): huks.HuksParam[] {
  return [{
    tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
    value: huks.HuksKeyAlg.HUKS_ALG_AES
  }, {
    tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
    value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
  }, {
    tag: huks.HuksTag.HUKS_TAG_PURPOSE,
    value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
  }];
}

function cipherProps(purpose: huks.HuksKeyPurpose, nonce: Uint8Array): huks.HuksParam[] {
  return [{
    tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
    value: huks.HuksKeyAlg.HUKS_ALG_AES
  }, {
    tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
    value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
  }, {
    tag: huks.HuksTag.HUKS_TAG_PURPOSE,
    value: purpose
  }, {
    tag: huks.HuksTag.HUKS_TAG_PADDING,
    value: huks.HuksKeyPadding.HUKS_PADDING_NONE
  }, {
    tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
    value: huks.HuksCipherMode.HUKS_MODE_GCM
  }, {
    tag: huks.HuksTag.HUKS_TAG_NONCE,
    value: nonce
  }, {
    tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
    value: utf8Bytes(AAD_TEXT)
  }];
}

export class PwdCrypto {

  /** 密钥只需确认/生成一次 */
  private static keyReady = false;

  /** 确认/生成 HUKS 密钥（不存在则生成） */
  static async ensureKey(): Promise<void> {
    if (PwdCrypto.keyReady) {
      return;
    }
    const options: huks.HuksOptions = { properties: genProperties() };
    const exists: boolean = await huks.isKeyItemExist(KEY_ALIAS, options);
    if (!exists) {
      await huks.generateKeyItem(KEY_ALIAS, options);
    }
    PwdCrypto.keyReady = true;
  }

  /**
   * 加密：enc1: + base64(nonce(12) + 密文 + tag(16))
   */
  static async encrypt(plain: string): Promise<string> {
    await PwdCrypto.ensureKey();
    const nonce: Uint8Array = cryptoFramework.createRandom().generateRandomSync(NONCE_LEN).data;
    const initRes: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, {
      properties: cipherProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce)
    });
    const finishRes: huks.HuksReturnResult = await huks.finishSession(initRes.handle, {
      properties: [],
      inData: utf8Bytes(plain)
    });
    const cipher: Uint8Array | undefined = finishRes.outData;
    if (cipher === undefined) {
      throw new Error('[PwdCrypto] encrypt: no outData');
    }
    const blob: Uint8Array = new Uint8Array(NONCE_LEN + cipher.length);
    blob.set(nonce, 0);
    blob.set(cipher, NONCE_LEN);
    return ENCRYPTED_PREFIX + new util.Base64Helper().encodeToStringSync(blob);
  }

  /**
   * 解密：非 enc1: 前缀（历史明文）原样返回；解密失败抛异常由调用方兜底
   */
  static async decrypt(stored: string): Promise<string> {
    if (!stored.startsWith(ENCRYPTED_PREFIX)) {
      return stored;
    }
    await PwdCrypto.ensureKey();
    const blob: Uint8Array = new util.Base64Helper()
      .decodeSync(stored.substring(ENCRYPTED_PREFIX.length));
    if (blob.length <= NONCE_LEN + TAG_LEN) {
      throw new Error('[PwdCrypto] decrypt: invalid blob');
    }
    const nonce: Uint8Array = blob.slice(0, NONCE_LEN);
    const tag: Uint8Array = blob.slice(blob.length - TAG_LEN);
    const cipher: Uint8Array = blob.slice(NONCE_LEN, blob.length - TAG_LEN);
    const props: huks.HuksParam[] = cipherProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce);
    props.push({
      tag: huks.HuksTag.HUKS_TAG_AE_TAG,
      value: tag
    });
    const initRes: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, {
      properties: props
    });
    const finishRes: huks.HuksReturnResult = await huks.finishSession(initRes.handle, {
      properties: [],
      inData: cipher
    });
    const plain: Uint8Array | undefined = finishRes.outData;
    if (plain === undefined) {
      throw new Error('[PwdCrypto] decrypt: no outData');
    }
    return utf8Text(plain);
  }

  /** 是否为加密存储格式 */
  static isEncrypted(stored: string): boolean {
    return stored.startsWith(ENCRYPTED_PREFIX);
  }
}
