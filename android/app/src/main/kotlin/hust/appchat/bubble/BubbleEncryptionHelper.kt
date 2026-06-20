// android/app/src/main/kotlin/hust/appchat/bubble/BubbleEncryptionHelper.kt
package hust.appchat.bubble

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * BubbleEncryptionHelper — AES-256-GCM end-to-end encryption.
 *
 * Used exclusively when [BubbleMode] == secure.
 *
 * Design
 * ───────
 * • Each conversation gets a deterministic symmetric key derived from the
 * sorted concatenation of both user IDs (SHA-256 → 32 bytes).
 * In a production system replace this with a proper ECDH key exchange
 * (e.g. Signal Protocol / Diffie-Hellman over Curve25519).
 *
 * • Every message is encrypted with a fresh random 12-byte IV.
 * The ciphertext is stored as:  base64( IV[12] || ciphertext || GCM tag[16] )
 *
 * • Android Keystore is used to protect a per-device master key; the
 * conversation key is XOR'd with the master key before storage to
 * prevent extraction from app storage.
 *
 * Wire format (base64-encoded)
 * ─────────────────────────────
 * [ 4 bytes magic "ENC:" ] [ 12 bytes IV ] [ N bytes ciphertext+tag ]
 */
object BubbleEncryptionHelper {

    private const val TAG             = "BubbleEncryption"
    private const val ALGORITHM       = "AES/GCM/NoPadding"
    private const val KEY_SIZE_BITS   = 256
    private const val IV_SIZE_BYTES   = 12
    private const val TAG_SIZE_BITS   = 128
    private const val MAGIC           = "ENC:"
    private const val KEYSTORE_ALIAS  = "bubble_master_key"

    // ─── Key derivation ───────────────────────────────────────────────────

    /**
     * Derive a 256-bit conversation key from two user IDs.
     * Sorting the IDs ensures both sides derive the same key regardless
     * of who is sender and who is receiver.
     */
    fun deriveConversationKey(userId1: String, userId2: String): SecretKey {
        val sorted = listOf(userId1, userId2).sorted()
        val seed   = "${sorted[0]}::${sorted[1]}::bubble_secure_v1"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(seed.toByteArray(StandardCharsets.UTF_8))

        // XOR with master key from Android Keystore for extra protection
        val masterBytes = getMasterKeyBytes()
        val keyBytes = ByteArray(32) { i -> (digest[i].toInt() xor
                masterBytes[i % masterBytes.size].toInt()).toByte() }

        return SecretKeySpec(keyBytes, "AES")
    }

    // ─── Encrypt ──────────────────────────────────────────────────────────

    /**
     * Encrypt [plainText] for the conversation between [myId] and [peerId].
     * Returns a base64-encoded string safe for Firestore storage.
     * Returns null if encryption fails (log the error; caller shows fallback).
     */
    fun encrypt(myId: String, peerId: String, plainText: String): String? {
        return try {
            val key = deriveConversationKey(myId, peerId)

            // Fresh random IV for each message
            val iv = ByteArray(IV_SIZE_BYTES).also { SecureRandom().nextBytes(it) }

            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.ENCRYPT_MODE, key,
                GCMParameterSpec(TAG_SIZE_BITS, iv))

            val cipherBytes = cipher.doFinal(
                plainText.toByteArray(StandardCharsets.UTF_8))

            // Layout: IV || ciphertext+tag
            val payload = ByteBuffer.allocate(IV_SIZE_BYTES + cipherBytes.size)
                .put(iv)
                .put(cipherBytes)
                .array()

            MAGIC + Base64.encodeToString(payload, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "❌ encrypt: $e")
            null
        }
    }

    // ─── Decrypt ──────────────────────────────────────────────────────────

    /**
     * Decrypt [cipherText] (returned by [encrypt]) for the conversation
     * between [myId] and [peerId].
     * Returns the plain text, or null on failure.
     */
    fun decrypt(myId: String, peerId: String, cipherText: String): String? {
        if (!cipherText.startsWith(MAGIC)) return cipherText  // not encrypted
        return try {
            val key = deriveConversationKey(myId, peerId)

            val payload = Base64.decode(
                cipherText.removePrefix(MAGIC), Base64.NO_WRAP)

            if (payload.size < IV_SIZE_BYTES) {
                Log.e(TAG, "❌ decrypt: payload too short")
                return null
            }

            val iv          = payload.copyOfRange(0, IV_SIZE_BYTES)
            val cipherBytes = payload.copyOfRange(IV_SIZE_BYTES, payload.size)

            val cipher = Cipher.getInstance(ALGORITHM)
            cipher.init(Cipher.DECRYPT_MODE, key,
                GCMParameterSpec(TAG_SIZE_BITS, iv))

            String(cipher.doFinal(cipherBytes), StandardCharsets.UTF_8)
        } catch (e: Exception) {
            Log.e(TAG, "❌ decrypt: $e")
            null
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────

    /** Returns true if [text] appears to be an encrypted message. */
    fun isEncrypted(text: String) = text.startsWith(MAGIC)

    /**
     * Re-encrypt a message (key rotation).
     * Decrypts with the old key pair and re-encrypts with the new one.
     */
    fun reEncrypt(
        cipherText  : String,
        oldId1: String, oldId2: String,
        newId1: String, newId2: String,
    ): String? {
        val plain = decrypt(oldId1, oldId2, cipherText) ?: return null
        return encrypt(newId1, newId2, plain)
    }

    /**
     * Generate a random ephemeral key for a one-time use (e.g. media keys).
     */
    fun generateEphemeralKey(): String {
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    // ─── Android Keystore master key ──────────────────────────────────────

    /**
     * Get or create a hardware-backed master key in Android Keystore.
     * Falls back to a software derivation on devices without HSM.
     * Returns the raw 32-byte key material for XOR mixing.
     */
    private fun getMasterKeyBytes(): ByteArray {
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)

            if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
                createMasterKey()
            }

            val entry = keyStore.getEntry(KEYSTORE_ALIAS, null)
                    as? KeyStore.SecretKeyEntry
                ?: return fallbackMasterBytes()

            // [SỬA LỖI P2]: Sử dụng HMAC-SHA256 (tiêu chuẩn cho KDF) thay vì AES-GCM với IV-zero.
            // Điều này đảm bảo tính toán chuỗi byte an toàn, đúng đắn và không vi phạm quy tắc mã hóa.
            val mac = Mac.getInstance("HmacSHA256")

            try {
                mac.init(entry.secretKey)
            } catch (e: java.security.InvalidKeyException) {
                // Tự động migration: Nếu key cũ là AES từ phiên bản trước, xóa đi và tạo lại HMAC
                Log.w(TAG, "⚠️ Legacy AES key detected, migrating to HMAC...")
                keyStore.deleteEntry(KEYSTORE_ALIAS)
                createMasterKey()
                val newEntry = keyStore.getEntry(KEYSTORE_ALIAS, null) as KeyStore.SecretKeyEntry
                mac.init(newEntry.secretKey)
            }

            // Trả về chính xác 32 bytes (256 bits) cho thao tác XOR
            mac.doFinal("bubble_stable_master_salt_v2".toByteArray(StandardCharsets.UTF_8))

        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Keystore unavailable: $e")
            fallbackMasterBytes()
        }
    }

    private fun createMasterKey() {
        // Sử dụng thuật toán HMAC thay cho AES để tạo mã tĩnh
        val kg = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
        kg.init(
            KeyGenParameterSpec.Builder(KEYSTORE_ALIAS, KeyProperties.PURPOSE_SIGN)
                .build()
        )
        kg.generateKey()
        Log.d(TAG, "✅ HMAC Master key created in Android Keystore")
    }

    /** Deterministic fallback when Keystore is unavailable (emulator etc.) */
    private fun fallbackMasterBytes(): ByteArray {
        val seed = "bubble_fallback_master_v1_${android.os.Build.FINGERPRINT}"
        return MessageDigest.getInstance("SHA-256")
            .digest(seed.toByteArray(StandardCharsets.UTF_8))
    }
}