<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.md">English</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# वॉचडॉग

एनवीडिया जीपीयू के लिए विंडोज वीआरएएम / रैम / अस्थायी वॉचडॉग। यह हर 2 सेकंड में नमूना लेता है। लगातार तीन उल्लंघनों के बाद, यह केवल उन इंटरप्रेटरों को मारता है जिनकी आपने सूची दी है - और जब कोई उल्लंघन कुछ भी नहीं करता है तो यह ऐसा ही बताता है।

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

हृदय गति-आयु जांच को स्वयं न बनाएं। `_watchdog` पर प्रक्रिया मिलान न करें। ये दो गलतियाँ हैं जिनके कारण एक मृत वॉचडॉग और एक स्वस्थ वॉचडॉग समान दिखते हैं।

**v1 केवल विंडोज के लिए है** (पावरशेल 7, एनवीडिया-एसएमआई, डब्ल्यूडीडीएम प्रक्रिया-मेमोरी काउंटर, वैकल्पिक डब्ल्यूएसएल `pkill`)। लिनक्स एक बाद का संस्करण है।

## स्थापित करें

पावरशेल 7.1+। क्लोन करें, उदाहरण कॉन्फ़िगरेशन की प्रतिलिपि बनाएं, संपादित करें, प्रारंभ करें:

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

या मॉड्यूल आयात करें:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` मॉड्यूल को आपके करंटयूज़र मॉड्यूल पथ में कॉपी करता है।

## कॉन्फ़िगरेशन

**कोई डिफ़ॉल्ट रूट और कोई डिफ़ॉल्ट किल सूची नहीं है।** मॉड्यूल बिना कॉन्फ़िगरेशन के शुरू होने से इनकार कर देता है। खोज क्रम: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`।

आवश्यक फ़ील्ड: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`। सापेक्ष पथ अस्वीकार किए जाते हैं। लेखन `Root` के अंतर्गत रहते हैं।

`VramKillMiB = 31200` एक 32 जीबी कार्ड (~1.4 जीबी, 32607 MiB डब्ल्यूडीडीएम सीमा से नीचे) के लिए प्रलेखित सीमा है। कॉम्फीयूआई ट्रिप्स को रोकने के लिए इसे न बढ़ाएं - इसके बजाय कॉम्फीयूआई (`--reserve-vram`) को सीमित करें।

## कमांड

| कमांड | यह क्या करता है |
|---|---|
| `watchdog status` | लाइवनेस। एकमात्र सही जांच। |
| `watchdog start -AllowKill` | सेंटिनल-स्टॉप, प्रतीक्षा करें, साफ़ करें, अलग लॉन्च करें, हृदय गति सत्यापित करें |
| `watchdog stop` | सेंटिनल को रोकें, प्रतीक्षा करें। कभी भी प्रक्रिया मिलान न करें। |
| `watchdog poll` | एक बार: यदि हृदय गति स्थिर है, तो बाहर से `_watchdog_DEAD` लिखें |
| `watchdog help` | फ्लैग और एग्जिट कोड |
| `watchdog version` | `1.0.0` |

`status` / `poll` एग्जिट कोड: **0** चल रहा है · **1** कोई हृदय गति नहीं · **2** स्थिर। `start` भी **3** (वीआरएएम पहले से ही सीमा से ऊपर), **4** (पुराना लूप बंद नहीं हुआ), **5** (लॉन्च के बाद कोई हृदय गति नहीं) का उपयोग करता है।

स्थिति पर `-Hook` क्लाउड कोड सेशनस्टार्ट जेएसओएन उत्सर्जित करता है और हमेशा 0 से बाहर निकलता है ताकि एक मृत वॉचडॉग सत्र शुरू होने को बाधित न कर सके।

## यह क्या मारता है

केवल वे `python` प्रक्रियाएँ जिनकी `Path`, `Targets` में है, साथ ही एक वैकल्पिक डब्ल्यूएसएल `pkill -f` पैटर्न (खाली = अक्षम)। अन्य पायथन को बचाया जाता है। एक उल्लंघन जो कुछ भी मेल नहीं खाता है, वह `_watchdog_NO_TARGET` लिखता है - यह एक सुरक्षा **अंतराल** है, सफलता नहीं।

सहमति: `-AllowKill` (या कॉन्फ़िगरेशन में `AllowKill = $true`)। पोलर कभी भी मारता नहीं है और कभी भी स्वचालित रूप से पुनरारंभ नहीं करता है; स्वचालित पुनरारंभ एक लाइव नौकरी को रद्द कर सकता है।

## खतरा मॉडल

- **प्रभावित:** `Root` (हृदय गति, सीएसवी, किल/कंसोल/क्रैश लॉग, सेंटिनल) के अंतर्गत फ़ाइलें; प्रक्रिया सूची; जीपीयू काउंटर; वैकल्पिक स्थानीय डब्ल्यूएसएल पीकिल।
- **अप्रभावित:** आपका स्रोत ट्री, चेकपॉइंट, क्रेडेंशियल, नेटवर्क।
- **अनुमतियाँ:** जो उपयोगकर्ता इसे शुरू करता है वह कॉन्फ़िगर किए गए इंटरप्रेटरों को मार सकता है। कोई अतिरिक्त सेवा खाता नहीं है।
- **कोई टेलीमेट्री नहीं** मशीन छोड़ती है। लॉग में कोई गुप्त जानकारी नहीं।
- **अपरिवर्तनीय कार्रवाई:** रद्द करें। [docs/compensators.md](docs/compensators.md) देखें।

## परीक्षण

```powershell
pwsh -File .\verify.ps1
```

32 यूनिट परीक्षण, कोई जीपीयू नहीं। पार्सर फिक्स्चर में गलत एनवीडिया-एसएमआई आउटपुट शामिल है जिसने 12-06-2026 को लूप को मार दिया। हार्डवेयर रद्द करने का परीक्षण स्थानीय रहता है और सीआई में हरा नहीं होता है।

## उत्पत्ति

यह पहले से ही 5090 पर चल रहे वॉचडॉग का एक निष्कर्षण है। पूर्व-निष्कर्षण स्क्रिप्ट को [`origin/`](origin/) के अंतर्गत SHA-256 पिन के साथ जमा कर दिया गया है। दिनांकित घटनाएं (पार्स क्रैश, पांच सप्ताह का अंतराल, असुरक्षित एआई-टूलकिट, 153 खाली रद्द करना, एक-नमूना मृत्यु) [docs/incidents.md](docs/incidents.md) में हैं।

## लाइसेंस

एमआईटी। [LICENSE](LICENSE) देखें। समर्थित: 1.x।

[एमसीपी टूल शॉप](https://mcp-tool-shop.github.io/) द्वारा निर्मित।
