# 靈魂配對測量儀 隱私權政策

最後更新：2026-10-06

「靈魂配對測量儀」（以下稱「本 App」）是一個娛樂用的小遊戲。我們不收集任何可以辨識你身分的資料。為了讓配對結果自動送達對方，本 App 只會上傳測量序號；網頁版的「報告合照」（預設開啟，可以關閉）另外會上傳一格熱度資料。說明如下。

## 我們不收集個人資料

- 本 App **沒有帳號**，不會要求你的姓名、電話、信箱或任何聯絡方式。
- 本 App **不使用**任何廣告、分析或追蹤工具。
- 本 App 唯一會連上網路的地方，是下面說明的「配對中繼」。

## 配對中繼

- 兩個人配對時，後測的一方測量完成後，本 App 會**自動**把「雙方的測量序號」送到中繼伺服器，讓先測的一方不用手動輸入就能收到結果。
- 先測的一方在等待期間，本 App 會用自己的序號向中繼伺服器查詢對方是否已回傳。
- App 上傳的內容**只有測量序號**；網頁版開啟「報告合照」時另外會上傳熱度資料，見下面「網頁版」。序號只代表你選的三個答案，不含姓名、裝置識別碼或任何個人資料。
- 中繼伺服器上的序號最多保存 **24 小時**，之後自動刪除。
- 知道某組序號的人，可以在這 24 小時內查到回傳給它的那組序號。
- 中繼伺服器架設在 Cloudflare。和所有網路服務一樣，連線時 Cloudflare 會處理 IP 位址等連線資訊；我們只用它來限制短時間內的大量請求，不會保存，也不會用來辨識你。
- 沒有網路時，仍然可以用手動輸入序號的方式完成配對。

## 相機

- 本 App 會使用前鏡頭，把畫面即時模擬成「熱像」效果。
- 畫面**只在你的手機上即時處理**，不會錄影，也不會上傳。
- 測量完成的那一刻，本 App 會留下當下那一格熱像畫面，當作收據與報告的背景。它只暫存在 App 執行期間，關掉 App 就消失；只有在你按下「匯出熱像報告」時，才會成為報告圖片的一部分，由你決定存到哪裡、傳給誰。
- 你可以拒絕相機權限，App 會改用靜態圖片，功能照常可以使用。

## 相簿

- 只有在你按下「匯出熱像報告」並選擇「儲存影像」時，本 App 才會把報告圖片**加入**你的相簿。
- 本 App **不會讀取**你相簿裡的任何照片。

## 存在手機上的資料

- 你的歷史紀錄只存在你的手機上，用來讓你關掉 App 後可以繼續配對。測量序號除了存在手機上，只會依上面「配對中繼」的說明上傳。
- 歷史紀錄可以在「紀錄」頁按「清空紀錄」刪除；刪除 App 會移除所有資料。

## 複製與分享

- 序號只會在**你主動按下複製**時放進剪貼簿，由你自己貼給對方。
- 報告圖片只會在**你主動按下匯出**時，透過系統分享選單傳給你選擇的對象。
- 除了上面「配對中繼」說明的測量序號，本 App 不會自動傳送任何內容。

## 網頁版

本 App 另有網頁版，以上原則同樣適用，另外說明如下：

- 網頁版**沒有帳號**，也**不使用**任何廣告、分析或追蹤工具。除了載入網頁本身與上面說明的「配對中繼」，不會再連上網路。
- 你的紀錄只存在**你這台裝置的瀏覽器**裡，我們看不到。測量序號只會依「配對中繼」的說明上傳；熱度資料只會依下面「報告合照」的說明上傳。清除瀏覽器的網站資料就會全部刪除；使用私密瀏覽時不會保留。
- 網頁版會在你第一次點擊畫面後，請瀏覽器詢問是否允許使用前鏡頭，用來把畫面即時模擬成「熱像」效果。鏡頭畫面**只在你的瀏覽器裡即時處理**，不會錄影，鏡頭畫面本身也不會上傳。你可以拒絕，網頁會改用靜態圖片，功能照常可以使用。
- 測量完成的那一刻，網頁會留下當下那一格熱像畫面，當作收據與報告的背景。它只暫存在這個分頁裡，關掉或重新整理就消失；只有在你按下「匯出熱像報告」時，才會成為報告圖片的一部分，由你決定存到哪裡、傳給誰。
- **報告合照（預設開啟，可以關閉）**：網頁版預設會交換雙方的熱度資料，讓兩邊的報告都出現對方的熱像。你可以在「設定」關閉「報告合照」，關閉之後的測量就不會上傳或保存熱度資料。開啟時的做法如下：
  - 網頁會把測量完成那一格熱像縮成一格**熱度數值**（96×128 格，每格只有冷熱程度）。它不是照片，沒有顏色，但畫出來和你在畫面上看到的熱像差不多清楚，看得出臉的輪廓與五官，認識你的人可能認得出來。
  - 這格熱度資料會送到中繼伺服器：先測的一方在按下複製序號時送出；後測的一方在測量完成、回傳序號時一起送出。
  - 熱度資料和序號一樣，在中繼伺服器上最多保存 **24 小時**，之後自動刪除。
  - 先測一方的熱度資料，只會交給第一個回傳序號給它的人；後測一方的熱度資料，只會交給先測的那台裝置。光是知道序號查不到熱度資料。
  - 你和對方的熱度資料會跟著那筆紀錄存在你的瀏覽器裡，讓你之後重開報告時還看得到合照；清空紀錄或清除網站資料就會刪除。
  - 你關閉了「報告合照」或拒絕相機權限時，不會上傳也不會保存你的熱度資料；對方關閉時，你的熱度資料不會交給對方。這些情況下報告改用靜態圖片。
- 網頁版不會讀取你的相簿。
- 放進剪貼簿的內容只有你的序號。序號只代表你選的三個答案，不含任何個人資料。
- 和所有網站一樣，開啟網頁時，網站主機可能會記錄 IP 位址等連線資訊；我們不會取得或使用這些資訊。

## 兒童

本 App 不針對兒童設計，也不會收集任何人的個人資料。

## 聯絡我們

如對本政策有任何疑問，請來信：[soulmatchmeter@gmail.com](mailto:soulmatchmeter@gmail.com)

---

# Soul Match Meter Privacy Policy

Last updated: 2026-10-06

Soul Match Meter ("the App") is an entertainment app. We do not collect any data that identifies you. To deliver a match result to the other person automatically, the App uploads measurement serials only; the web version's "Pair photo" (on by default; you can turn it off) also uploads a heat grid. Details are below.

- **No personal data.** The App has no accounts and never asks for your name, phone number, email, or any contact details. It uses no advertising, analytics, or tracking tools. The only time it uses the network is the pairing relay below.
- **Pairing relay.** When two people pair, the App of the person who measures second automatically sends both measurement serials to a relay server, so the first person receives the result without typing it in. While waiting, the first person's App asks the relay, using its own serial, whether a reply has arrived. The App uploads serials only (the web version also uploads a heat grid when "Pair photo" is on, see below); a serial encodes your three answers and contains no name, device identifier, or personal data. Serials are kept on the relay for at most 24 hours and then deleted automatically. Anyone who knows a serial can look up the reply sent to it during those 24 hours. The relay runs on Cloudflare; as with any network service, Cloudflare processes connection details such as IP addresses. We use them only to limit bursts of requests, and do not store them or use them to identify you. Without a network connection, pairing still works by typing the serial in.
- **Camera.** The front camera is used to render a simulated thermal view. Frames are processed on your device in real time and are never recorded or uploaded. The single frame frozen when a measurement completes is kept only while the App is running, as the backdrop of the receipt and the report, and becomes part of a report image only if you export one. You can deny camera access and the App still works.
- **Photos.** The App only adds an image to your photo library when you export a report and choose "Save Image". It never reads your photos.
- **On-device data.** Your history is stored only on your device so you can resume a pairing. Serials are stored on your device and uploaded only as described under the pairing relay. You can clear the history on the Log screen; deleting the App removes all of it.
- **Copying and sharing.** Your serial goes to the clipboard only when you choose to copy it, for you to paste to the other person. Report images are sent only when you choose to export them through the system share sheet. Apart from the serials described under the pairing relay, the App never sends anything on its own.
- **Web version.** The web version has no accounts and no advertising, analytics, or tracking, and uses the network only to load the page itself and for the pairing relay described above. Your history stays in your browser's storage on your device; clearing the site's data removes it. After your first tap it asks the browser for the front camera, to render a simulated thermal view. Camera frames are processed in your browser in real time and are never recorded, and the frames themselves are never uploaded; you can decline and it uses still images instead. The single frame frozen when a measurement completes is kept only in the open tab, as the backdrop of the receipt and the report, and becomes part of a report image only if you export one. **Pair photo (on by default; you can turn it off):** by default the web version swaps both people's heat grids so each report shows the other person's thermal image. You can turn "Pair photo" off in Settings; measurements taken after that upload and save no heat grid. While it is on, the frozen frame is reduced to a grid of heat values (96×128 cells, each holding only how warm it is). It is not a photo and has no colour, but drawn out it is about as clear as the thermal view you see on screen: the outline of a face and its features can be made out, and someone who knows you may recognise you. The grid is sent to the relay: by the person who measures first when they copy their serial, and by the person who measures second together with their reply. Like serials, grids are kept on the relay for at most 24 hours and then deleted automatically. The first person's grid is given only to the first person who replies to their serial; the second person's grid is given only to the first person's device. Knowing a serial is not enough to look a grid up. Both grids are saved with that entry in your browser's storage so the report still shows the pair later; clearing the log or the site's data removes them. If you have "Pair photo" off or decline the camera, your heat grid is neither uploaded nor saved; if the other person has it off, your grid is not given to them. In those cases the report uses still images. It never reads your photos. Copying puts only your serial on the clipboard; it encodes only your three answers. As with any website, the host may log connection details such as IP addresses when the page is opened; we do not obtain or use them.

Contact: [soulmatchmeter@gmail.com](mailto:soulmatchmeter@gmail.com)
