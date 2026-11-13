// Bounded structural/type validation ONLY. No antivirus, no external service.
import { Buffer } from 'node:buffer';
import { inflateRawSync } from 'node:zlib';

export const MAX = 5242880;
const fail = () => { throw Error('Unsupported, unsafe or malformed file.'); };
function dimensions(width, height) {
  if (!width || !height || width > 12000 || height > 12000 || width * height > 25000000) fail();
}
function crc32(data) {
  let crc = -1;
  for (const byte of data) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ -1) >>> 0;
}
function zipEntries(b) {
  if (b.length < 22 || b.readUInt32LE(0) !== 0x04034b50) fail();
  // No ZIP64, encrypted entries, duplicate names, nested archives or expansion bombs.
  let end = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b.readUInt32LE(i) === 0x06054b50 && i + 22 + b.readUInt16LE(i + 20) === b.length) { end = i; break; }
  }
  if (end < 0 || b.readUInt16LE(end + 4) || b.readUInt16LE(end + 6)) fail();
  const count = b.readUInt16LE(end + 10), entries = new Map();
  if (count < 2 || count > 256 || count !== b.readUInt16LE(end + 8)) fail();
  let offset = b.readUInt32LE(end + 16), expanded = 0;
  const directoryEnd = offset + b.readUInt32LE(end + 12);
  if (directoryEnd !== end) fail();
  for (let i = 0; i < count; i++) {
    if (offset + 46 > end || b.readUInt32LE(offset) !== 0x02014b50) fail();
    const flags = b.readUInt16LE(offset + 8), method = b.readUInt16LE(offset + 10);
    const size = b.readUInt32LE(offset + 24), compressed = b.readUInt32LE(offset + 20);
    const nameLength = b.readUInt16LE(offset + 28), extra = b.readUInt16LE(offset + 30), comment = b.readUInt16LE(offset + 32);
    const name = b.subarray(offset + 46, offset + 46 + nameLength).toString('utf8');
    if ((flags & ~0x0808) || ![0, 8].includes(method) || name.includes('..') || name.includes('\\') || name.startsWith('/') ||
        /[\x00-\x1f]/.test(name) || entries.has(name) || /vba|macro|activex|embeddings|externallinks|\.(zip|exe|dll|bin|com|scr|msi|js|vbs|ps1|cmd|bat|jar|hta|html|htm|svg|xhtml)$/i.test(name)) fail();
    const local = b.readUInt32LE(offset + 42);
    if (local + 30 > offset || b.readUInt32LE(local) !== 0x04034b50 || b.readUInt16LE(local + 8) !== method ||
        b.readUInt16LE(local + 6) !== flags) fail();
    const ln = b.readUInt16LE(local + 26), le = b.readUInt16LE(local + 28);
    if (b.subarray(local + 30, local + 30 + ln).toString('utf8') !== name) fail();
    const start = local + 30 + ln + le;
    expanded += size;
    if (expanded > 33554432 || size > 16777216 || size > Math.max(1, compressed) * 100 || start + compressed > b.readUInt32LE(end + 16)) fail();
    const bytes = method === 0 ? b.subarray(start, start + compressed) : inflateRawSync(b.subarray(start, start + compressed), { maxOutputLength: 16777216 });
    if (bytes.length !== size || crc32(bytes) !== b.readUInt32LE(offset + 16)) fail();
    if (/\.(xml|rels)$/i.test(name) && (bytes.includes(0) || /<!DOCTYPE|<!ENTITY|TargetMode\s*=\s*["'](?!Internal["'])|attachedTemplate|oleObject/i.test(bytes.toString('utf8')))) fail();
    entries.set(name, bytes);
    offset += 46 + nameLength + extra + comment;
  }
  if (offset !== directoryEnd) fail();
  return entries;
}
export function validateFile(input, name, claimedMime) {
  const b = Buffer.from(input);
  if (!b.length || b.length > MAX || typeof name !== 'string' || [...name].length > 255 || /[\x00-\x1f\x7f/\\]/.test(name)) fail();
  const ext = name.split('.').pop().toLowerCase(); let mime;
  if (['jpg', 'jpeg'].includes(ext)) {
    if (b.length < 12 || b.readUInt16BE(0) !== 0xffd8 || b.readUInt16BE(b.length - 2) !== 0xffd9) fail();
    let i = 2, found = false, foundScan = false;
    while (i + 4 < b.length) {
      if (b[i++] !== 0xff) fail();
      while (b[i] === 0xff) i++;
      const marker = b[i++];
      if (marker === 0xda) {
        const scanLength = b.readUInt16BE(i);
        if (scanLength < 6 || i + scanLength >= b.length - 2) fail();
        foundScan = true; break;
      }
      const length = b.readUInt16BE(i);
      if (length < 2 || i + length > b.length) fail();
      if ([0xc0,0xc1,0xc2].includes(marker)) { if (length < 8) fail(); dimensions(b.readUInt16BE(i + 5), b.readUInt16BE(i + 3)); found = true; }
      i += length;
    }
    if (!found || !foundScan) fail(); mime = 'image/jpeg';
  } else if (ext === 'png') {
    if (!b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) fail();
    let i = 8, first = true, end = false, image = false;
    while (i + 12 <= b.length) {
      const length = b.readUInt32BE(i), type = b.toString('ascii', i + 4, i + 8);
      if (i + 12 + length > b.length || first && (type !== 'IHDR' || length !== 13) ||
          crc32(b.subarray(i + 4, i + 8 + length)) !== b.readUInt32BE(i + 8 + length)) fail();
      if (first) dimensions(b.readUInt32BE(i + 8), b.readUInt32BE(i + 12));
      if (type === 'IDAT') image = true;
      i += 12 + length; first = false;
      if (type === 'IEND') { if (length !== 0 || i !== b.length) fail(); end = true; break; }
    }
    if (!end || !image) fail(); mime = 'image/png';
  } else if (ext === 'pdf') {
    const text = b.toString('latin1');
    if (!/^%PDF-(1\.[0-7]|2\.0)/.test(text) || !/%%EOF\s*$/.test(text) ||
        !/\/Type\s*\/Catalog\b/.test(text) || !/\/Type\s*\/Pages?\b/.test(text) ||
        /\/(Encrypt|JavaScript|JS|Launch|EmbeddedFile|RichMedia|XFA|AcroForm)\b/.test(text)) fail();
    mime = 'application/pdf';
  } else if (['docx','xlsx'].includes(ext)) {
    const entries = zipEntries(b), types = entries.get('[Content_Types].xml')?.toString('utf8') ?? '';
    const main = ext === 'docx' ? 'word/document.xml' : 'xl/workbook.xml';
    if (!entries.has('_rels/.rels') || !entries.has(main) || /macroEnabled/i.test(types) ||
        !types.includes(ext === 'docx' ? 'wordprocessingml.document.main+xml' : 'spreadsheetml.sheet.main+xml')) fail();
    mime = ext === 'docx' ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  } else fail();
  if (mime !== claimedMime) fail();
  return mime;
}
