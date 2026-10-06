// Copied verbatim from the app. Change the app first, then mirror it here.
//
// QUESTION_BANK, RESULT_TIERS, SNAPSHOT_META, toast and error text:
//   soul-match-meter/Model/MeterModel.swift
// Screen labels: soul-match-meter/Screens/*.swift (named per entry below)

export const QUESTION_BANK = [
  {
    text: '你現在最像哪種動物？',
    options: ['烏龜', '貓', '恐龍', '企鵝'],
    metric: '動物相容',
    lowerIsBetter: false,
  },
  {
    text: '手機剩 1% 電，你會？',
    options: ['直接關機裝死', '先傳「我電要沒了」', '邊充邊講兩小時', '問陌生人借線'],
    metric: '電量焦慮差',
    lowerIsBetter: true,
  },
  {
    text: '半夜肚子餓，你是？',
    options: ['鹹酥雞', '泡麵加蛋', '冰箱裡的剩菜', '忍住然後失眠'],
    metric: '宵夜同步',
    lowerIsBetter: false,
  },
  {
    text: '收到一句「在嗎？」，你會？',
    options: ['秒回「在」', '三小時後再回', '已讀然後忘記', '回「不在」'],
    metric: '回覆同步',
    lowerIsBetter: false,
  },
  {
    text: '週末的理想起床時間？',
    options: ['鬧鐘響之前', '早上十點', '中午以後', '週末沒有早上'],
    metric: '作息時差',
    lowerIsBetter: true,
  },
  {
    text: '出門前的最後一件事？',
    options: ['檢查瓦斯', '找鑰匙', '照鏡子', '回去拿忘記的東西'],
    metric: '出門延遲差',
    lowerIsBetter: true,
  },
  {
    text: '打開外送 App 之後，你會？',
    options: ['點上次那家', '滑二十分鐘再關掉', '專看評價最低的', '讓對方決定'],
    metric: '選擇障礙同步',
    lowerIsBetter: false,
  },
  {
    text: '你的手機桌布是？',
    options: ['預設桌布', '寵物', '某個風景', '一整片黑'],
    metric: '桌布相容',
    lowerIsBetter: false,
  },
  {
    text: '突然下雨又沒帶傘，你會？',
    options: ['直接衝', '等雨停', '買一把新的', '假裝很享受'],
    metric: '淋雨協議',
    lowerIsBetter: false,
  },
  {
    text: '朋友唱歌走音，你會？',
    options: ['跟著一起走音', '默默把伴唱調大', '鼓掌最大聲', '偷偷切下一首'],
    metric: '社交噪音差',
    lowerIsBetter: true,
  },
];

export const RESULT_TIERS = [
  { min: 95, title: '同一顆腦袋' },
  { min: 90, title: '出廠設定一樣' },
  { min: 84, title: '共用一條充電線' },
  { min: 78, title: '鹹酥雞搭檔' },
  { min: 72, title: '同一個 Wi-Fi 的兩台裝置' },
  { min: 66, title: '會互相按讚的鄰居' },
  { min: 60, title: '室友級靈魂' },
  { min: 54, title: '排隊剛好站前後' },
  { min: 48, title: '同一台電梯的陌生人' },
  { min: 42, title: '時差六小時' },
  { min: 36, title: '兩隻不同品種的貓' },
  { min: 0, title: '不同頻道的兩台電視' },
];

export const SNAPSHOT_META = 'PEAK 41.8 °C · ε 0.80';

export const TEXT = {
  // MeterModel.submitCode
  errShort: (length) => `ERR 07 · 序號不足 ${length} 碼`,
  errChecksum: 'ERR 09 · 校驗失敗，這個靈魂不存在',
  errOwn: 'ERR 11 · 這是你自己的序號',
  errWrongSet: 'ERR 13 · 題目對不上，這不是回給你的序號',

  // MeterModel.copyCode
  toastCopied: '序號已複製。去聊天室貼給他。',
  // Web only: the browser refused the clipboard. The app can't hit this.
  toastCopyFailed: '複製失敗，請手動抄下序號',
  // MeterModel.factoryReset, clearHistory
  toastReset: '已回復原廠設定',
  toastCleared: '紀錄已清空',

  // HomeScreen.swift
  homeStart: '我先開始測',
  homeHaveSerial: '我有對方的序號',
  homeSettings: '設定',
  homeHistory: '紀錄',
  pendingWaiting: '等待對方回傳',
  pendingUnread: '對方回傳了 · 看配對報告',
  hoursLeft: (hours) => `剩 ${hours} H`,
  hintWaiting: '回到收據',
  hintUnread: '開啟配對報告',

  // SerialEntryScreen.swift
  serialTitleReply: '輸入對方回傳的序號',
  serialTitleGuest: '輸入對方的測量序號',
  serialConfirm: '確認序號',
  keyRandom: '隨機序號',
  keyDelete: '刪除',
  back: '返回',

  // CalibrationScreen.swift
  close: '關閉',

  // HoldScreen.swift
  holdIdle: '按住',
  holdHolding: '別放',
  holdLocked: '好了',
  holdDropped: '手指離開就會冷掉，從 0.0s 重來。',

  // ReceiptScreen.swift
  receiptFootnote: '撕下，貼給對方。',
  receiptWaiting: '等待對方回傳。對方大概在洗澡。',
  receiptArrived: '對方已回傳。',
  receiptCopy: '複製序號 · 去貼給對方',
  receiptCopyAgain: '再複製一次',
  receiptNextHost: '對方回傳了 · 輸入他的序號',
  receiptNextArrived: '對方回傳了 · 看配對報告',

  // ReportScreen.swift
  reportExport: '匯出熱像報告',
  reportExported: '已匯出 · 再匯出一次',
  exportFooter: 'SOUL MATCH METER · 靈魂配對測量儀',
  reportAgain: '再測一次（結果會變）',
  confirmTitle: '確定要重測？',
  confirmYes: '重測',
  confirmNo: '留著',
  scoreLabel: (score) => `配對度 ${score} %`,

  // SettingsScreen.swift
  settingsChip: 'INSTRUMENT SETUP',
  settingsTitle: '設定',
  settingsNote: '這些設定完全不影響結果，但調起來很有感覺。',
  settingsDisclaimer: '娛樂用途，不會測量真實溫度。',
  settingPalette: '色盤',
  settingHold: '測量時長',
  settingShutter: '快門音效',
  // Web only: the app has no pair photo yet.
  settingPairPhoto: '報告合照',
  settingPairPhotoNote: '報告合照開啟時，會把你測量當下的熱像傳給對方，雙方都開啟才會出現合照。不想傳可以關閉。',
  holdOption: (seconds) => `${seconds} s`,
  toggleOn: 'ON',
  toggleOff: 'OFF',
  settingsReset: '回復原廠設定',

  // HistoryScreen.swift
  historyCount: (count) => `${count} SNAPSHOTS`,
  historyEmptyTitle: '還沒有任何測量紀錄',
  historyEmptyNote: '本機只保存 24 小時內的快照。目前是空的，這很正常。',
  historyFirst: '去測第一次',
  historyClear: '清空紀錄',
  stateWaiting: '等待回傳',
  stateUnread: '未讀',
  statePaired: '已配對',
  stateExpired: '已過期',
  stateScore: (score) => `${score} %`,
};
