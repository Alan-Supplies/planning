#!/usr/bin/env node
'use strict'

/**
 * Read-only Google Sheets reader (service-account auth).
 *
 * Usage:
 *   node read_sheet.js <spreadsheetId|url> [range]
 *   node read_sheet.js <url> --gid <gid>
 *   node read_sheet.js <id> --out <dir> --key <sa.json>
 *
 * Auth (in priority order):
 *   1. --key <path>                     explicit service-account JSON path
 *   2. $GOOGLE_APPLICATION_CREDENTIALS  path to service-account JSON  (권장)
 *
 * The sheet must be shared (viewer) with the service account's client_email.
 * Never commit the key — keep it OUTSIDE this repo (e.g. ~/.config/preppers/gsheets-sa.json, chmod 600).
 *
 * Output: prints a preview to stdout, and (unless --no-file) writes
 *   <title>__<sheet>.csv and <title>.json into --out (default: cwd).
 */

const fs = require('fs')
const path = require('path')
const { google } = require('googleapis')

const READONLY = 'https://www.googleapis.com/auth/spreadsheets.readonly'

function parseArgs(argv) {
  const opts = { positional: [], gid: null, range: null, out: process.cwd(), key: null, file: true }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--gid') opts.gid = argv[++i]
    else if (a === '--out') opts.out = argv[++i]
    else if (a === '--key') opts.key = argv[++i]
    else if (a === '--no-file') opts.file = false
    else if (a.startsWith('--')) fail(`알 수 없는 옵션: ${a}`)
    else opts.positional.push(a)
  }
  return opts
}

function fail(msg) {
  console.error(`\n[gsheet-reader] ${msg}\n`)
  process.exit(1)
}

/** Accepts a raw spreadsheetId or a full docs.google.com URL; returns {id, gid}. */
function extractId(input) {
  const idMatch = input.match(/\/spreadsheets\/d\/([a-zA-Z0-9-_]+)/)
  const gidMatch = input.match(/[?#&]gid=([0-9]+)/)
  return {
    id: idMatch ? idMatch[1] : input,
    gid: gidMatch ? gidMatch[1] : null,
  }
}

function resolveKeyFile(explicit) {
  const keyFile = explicit || process.env.GOOGLE_APPLICATION_CREDENTIALS
  if (!keyFile) {
    fail(
      '서비스 계정 키를 찾을 수 없습니다.\n' +
        '  방법 1) 환경변수:  export GOOGLE_APPLICATION_CREDENTIALS=~/.config/preppers/gsheets-sa.json\n' +
        '  방법 2) 옵션:      --key /path/to/sa.json\n' +
        '  그리고 시트를 서비스계정 이메일(client_email)에 뷰어로 공유하세요.'
    )
  }
  const resolved = keyFile.replace(/^~(?=$|\/)/, process.env.HOME || '')
  if (!fs.existsSync(resolved)) fail(`키 파일이 없습니다: ${resolved}`)
  return resolved
}

function toCsv(rows) {
  return rows
    .map((row) =>
      (row || [])
        .map((cell) => {
          const s = cell == null ? '' : String(cell)
          return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
        })
        .join(',')
    )
    .join('\n')
}

function sanitize(name) {
  return name.replace(/[^\w가-힣.-]+/g, '_').slice(0, 80)
}

function previewTable(rows, max = 12) {
  const slice = rows.slice(0, max)
  const widths = []
  for (const row of slice) {
    ;(row || []).forEach((c, i) => {
      widths[i] = Math.max(widths[i] || 0, String(c == null ? '' : c).length)
    })
  }
  for (const row of slice) {
    const line = (row || [])
      .map((c, i) => String(c == null ? '' : c).padEnd(widths[i]))
      .join(' | ')
    console.log('  ' + line)
  }
  if (rows.length > max) console.log(`  … (+${rows.length - max} rows)`)
}

async function main() {
  const opts = parseArgs(process.argv.slice(2))
  if (opts.positional.length === 0) {
    fail('사용법: node read_sheet.js <spreadsheetId|url> [range] [--gid <gid>] [--out <dir>] [--key <sa.json>]')
  }

  const { id, gid: gidFromUrl } = extractId(opts.positional[0])
  const gid = opts.gid || gidFromUrl
  const explicitRange = opts.positional[1] || null

  const auth = new google.auth.GoogleAuth({
    keyFile: resolveKeyFile(opts.key),
    scopes: [READONLY],
  })
  const sheets = google.sheets({ version: 'v4', auth })

  // Metadata: title + sheet list (needed to resolve gid → sheet name).
  const meta = await sheets.spreadsheets.get({
    spreadsheetId: id,
    fields: 'properties.title,sheets.properties(sheetId,title,index)',
  })
  const title = meta.data.properties.title
  const allSheets = meta.data.sheets.map((s) => s.properties)
  console.log(`\n📄 ${title}  (${allSheets.length} sheets)`)

  // Decide which sheets/ranges to fetch.
  let targets
  if (explicitRange) {
    targets = [{ label: explicitRange, range: explicitRange }]
  } else if (gid != null) {
    const found = allSheets.find((s) => String(s.sheetId) === String(gid))
    if (!found) fail(`gid=${gid} 에 해당하는 시트를 찾을 수 없습니다. 가능한 gid: ${allSheets.map((s) => s.sheetId).join(', ')}`)
    targets = [{ label: found.title, range: `'${found.title}'` }]
  } else {
    targets = allSheets.map((s) => ({ label: s.title, range: `'${s.title}'` }))
  }

  const dump = { spreadsheetId: id, title, sheets: {} }

  for (const t of targets) {
    const res = await sheets.spreadsheets.values.get({
      spreadsheetId: id,
      range: t.range,
      valueRenderOption: 'UNFORMATTED_VALUE',
      dateTimeRenderOption: 'FORMATTED_STRING',
    })
    const rows = res.data.values || []
    dump.sheets[t.label] = rows
    console.log(`\n── [${t.label}]  ${rows.length} rows ──`)
    previewTable(rows)

    if (opts.file) {
      const csvPath = path.join(opts.out, `${sanitize(title)}__${sanitize(t.label)}.csv`)
      fs.writeFileSync(csvPath, toCsv(rows))
      console.log(`  → ${csvPath}`)
    }
  }

  if (opts.file) {
    const jsonPath = path.join(opts.out, `${sanitize(title)}.json`)
    fs.writeFileSync(jsonPath, JSON.stringify(dump, null, 2))
    console.log(`\n→ ${jsonPath}\n`)
  }
}

main().catch((err) => {
  const reason = err && err.errors ? JSON.stringify(err.errors) : err && err.message ? err.message : String(err)
  fail(`실패: ${reason}`)
})
