export const buf2hex = (buffer: ArrayBuffer, prefix = true) =>
  `${prefix ? "0x" : ""}${[...new Uint8Array(buffer)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;

export const hex2buf = (hex: string) =>
  Uint8Array.from(
    hex
      .replace(/^0x/, "")
      .match(/.{1,2}/g)!
      .map((byte) => parseInt(byte, 16)),
  );

export const buf2base64 = (buffer: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));

export const buf2base64url = (buffer: ArrayBuffer) =>
  buf2base64(buffer).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

export const base64url2buf = (base64URLString: string) => {
  const base64 = base64URLString.replace(/-/g, "+").replace(/_/g, "/");
  const padLength = (4 - (base64.length % 4)) % 4;
  const padded = base64.padEnd(base64.length + padLength, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
};

export const randomBytes = (length: number) =>
  new Uint8Array(Array.from({ length }, () => Math.floor(Math.random() * 40)));

export const buf2bigint = (buffer: Uint8Array): bigint => {
  let value = 0n;
  for (const byte of buffer.values()) {
    value = (value << 8n) + BigInt(byte);
  }
  return value;
};

export function hexStringToUint8Array(hexString: string): Uint8Array {
  // Remove any leading 0x, if present
  hexString = hexString.replace(/^0x/, "");

  // Ensure the string has an even number of characters (two hex digits per byte)
  if (hexString.length % 2 !== 0) {
    hexString = "0" + hexString;
  }

  // Create a Uint8Array with the necessary length
  const byteArray = new Uint8Array(hexString.length / 2);

  // Convert each pair of hex characters into a byte
  for (let i = 0; i < hexString.length; i += 2) {
    byteArray[i / 2] = parseInt(hexString.substring(i, i + 2), 16);
  }

  return byteArray;
}
