<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.md">English</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://codecov.io/gh/mcp-tool-shop-org/watchdog"><img src="https://codecov.io/gh/mcp-tool-shop-org/watchdog/graph/badge.svg" alt="Coverage"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://mcp-tool-shop-org.github.io/watchdog/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
</p>

# वॉचडॉग

NVIDIA GPU के लिए विंडोज VRAM / RAM / अस्थायी वॉचडॉग। यह हर 2 सेकंड में नमूना लेता है। लगातार 3 उल्लंघनों के बाद, यह **केवल** उन इंटरप्रेटरों को बंद कर देता है जिनकी आपने सूची दी है — और जब कोई उल्लंघन कुछ भी बंद नहीं करता है, तो यह बताता है।

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

हृदय गति-आयु जांच को स्वयं न बनाएं। `_watchdog` पर प्रक्रिया मिलान न करें। ये दो गलतियाँ ही हैं जिनके कारण एक मृत वॉचडॉग और एक स्वस्थ वॉचडॉग एक जैसे दिखते हैं।

**v1 केवल विंडोज के लिए है** (PowerShell 7, nvidia-smi, WDDM प्रक्रिया-मेमोरी काउंटर, वैकल्पिक WSL `pkill` और WSL फ़ाइल-कैश रिलीज़)। लिनक्स एक बाद का संस्करण है।

## स्थापित करें

PowerShell 7.1+. क्लोन करें, उदाहरण कॉन्फ़िगरेशन की प्रतिलिपि बनाएं, संपादित करें, प्रारंभ करें:

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

`Install-Watchdog` मॉड्यूल को आपके CurrentUser मॉड्यूल पथ में कॉपी करता है।

## कॉन्फ़िगरेशन

**कोई डिफ़ॉल्ट रूट और कोई डिफ़ॉल्ट किल सूची नहीं है।** मॉड्यूल बिना कॉन्फ़िगरेशन के शुरू होने से इनकार करता है। खोज क्रम: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`।

आवश्यक फ़ील्ड: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`। सापेक्ष पथ अस्वीकार किए जाते हैं। लेखन `Root` के अंतर्गत रहते हैं।

`VramKillMiB = 31200` 32 GB कार्ड (~1.4 GB, 32607 MiB WDDM सीमा से नीचे) के लिए प्रलेखित सीमा है। ComfyUI ट्रिप्स को रोकने के लिए इसे न बढ़ाएं — इसके बजाय ComfyUI (`--reserve-vram`) को सीमित करें।

### WSL फ़ाइल-कैश रिलीज़ (ऑप्ट-इन / डिफ़ॉल्ट रूप से बंद)

`WslCacheRelease = $true` के साथ, प्रत्येक जांच विंडोज साइड से WSL VM की मेमोरी की जांच करती है (यह कभी भी रुके हुए VM को जगाता नहीं है)। जब `vmmemWSL` बड़ा होता है, या विंडोज मेमोरी पर दबाव होता है और `vmmemWSL` मध्यम आकार का होता है, तो पोलर `WslDistro` में लिनक्स पेज कैश को छोड़ देता है (`echo 1 > /proc/sys/vm/drop_caches` रूट के रूप में, टाइमआउट और कूलडाउन के साथ)। WSL का अपना `autoMemoryReclaim` केवल तभी सक्रिय होता है जब VM निष्क्रिय होता है, और एक चल रहा कंटेनर इंजन इसे व्यस्त रखता है, इसलिए बड़ी छवि डाउनलोड करने से विंडोज के विरुद्ध दसियों GB का कैश हो सकता है।

यह कभी भी किसी प्रक्रिया को समाप्त नहीं करता है, और न ही किसी बंद वितरण को शुरू करता है: जब कोई अन्य वितरण वीएम को चालू रखता है, जबकि `WslDistro` बंद है, तो यह कैश रिलीज़ को छोड़ देता है और इसे लॉग करता है। इसका लॉग, `Root\_watchdog_wslcache.log`, प्रति घंटे एक हार्टबीट रिकॉर्ड करता है; प्रत्येक कैश रिलीज़, जिसमें उससे पहले और बाद में मेमोरी होती है; लगातार स्किप की हर शृंखला के लिए एक पंक्ति; और एक `ALERT` जो शीर्ष प्रक्रियाओं का नाम देता है यदि रिलीज़ के बाद भी विंडोज `WslCacheAlertPct` से ऊपर है। सीमाएँ उदाहरण कॉन्फ़िगरेशन में दी गई हैं।

## कमांड

| कमांड | यह क्या करता है |
|---|---|
| `watchdog status` | लाइवनेस। एकमात्र सही जांच। |
| `watchdog start -AllowKill` | सेंटिनल-स्टॉप, प्रतीक्षा करें, साफ़ करें, अलग लॉन्च, हृदय गति सत्यापित करें |
| `watchdog stop` | सेंटिनल को रोकें, प्रतीक्षा करें। कभी भी प्रक्रिया मिलान न करें। |
| `watchdog poll` | एक बार: यदि हृदय गति स्थिर है, तो बाहर से `_watchdog_DEAD` लिखें |
| `watchdog help` | फ्लैग और निकास कोड |
| `watchdog version` | `1.1.1` |

`status` / `poll` निकास कोड: **0** चल रहा है · **1** कोई हृदय गति नहीं · **2** स्थिर। `start` भी **3** (VRAM पहले से ही सीमा से ऊपर), **4** (पुराना लूप नहीं रुका), **5** (लॉन्च के बाद कोई हृदय गति नहीं) का उपयोग करता है।

स्थिति पर `-Hook` क्लाउड कोड SessionStart JSON उत्सर्जित करता है और हमेशा 0 पर बाहर निकलता है ताकि एक मृत वॉचडॉग सत्र शुरू होने से न रोक सके।

## यह क्या बंद करता है

केवल वे `python` प्रक्रियाएँ जिनकी `Path` `Targets` में है, साथ ही एक वैकल्पिक WSL `pkill -f` पैटर्न (खाली = अक्षम)। अन्य पायथन को बचाया जाता है। एक उल्लंघन जो कुछ भी मेल नहीं खाता है, `_watchdog_NO_TARGET` लिखता है — यह एक सुरक्षा **अंतराल** है, सफलता नहीं।

सहमति: `-AllowKill` (या कॉन्फ़िगरेशन में `AllowKill = $true`)। पोलर कभी भी बंद नहीं करता है और कभी भी स्वचालित रूप से पुनरारंभ नहीं करता है; स्वचालित पुनरारंभ एक लाइव नौकरी को रोक सकता है।

## खतरा मॉडल

- **प्रभावित:** `Root` के अंतर्गत फ़ाइलें (हार्टबीट, CSV, किल/कंसोल/क्रैश लॉग, सेंटिनल); प्रक्रिया सूची; GPU काउंटर; वैकल्पिक स्थानीय WSL pkill; वैकल्पिक WSL पेज-कैश ड्रॉप (ऑप्ट-इन, कभी किसी प्रक्रिया को समाप्त नहीं करता)।
- **प्रभावित नहीं:** आपका स्रोत ट्री, चेकपॉइंट, क्रेडेंशियल, नेटवर्क।
- **अनुमतियाँ:** जो उपयोगकर्ता इसे शुरू करता है, वह कॉन्फ़िगर किए गए इंटरप्रेटरों को बंद कर सकता है। कोई अतिरिक्त सेवा खाता नहीं है।
- **कोई टेलीमेट्री नहीं** मशीन छोड़ती है। लॉग में कोई गुप्त जानकारी नहीं।
- **अपरिवर्तनीय कार्रवाई:** ABORT। [docs/compensators.md](docs/compensators.md) देखें।

## परीक्षण

```powershell
pwsh -File .\verify.ps1
```

132 यूनिट परीक्षण, कोई जीपीयू नहीं। पार्सर फिक्स्चर में विकृत nvidia-smi आउटपुट शामिल है, जिसने 2026-06-12 को लूप को समाप्त कर दिया। हार्डवेयर एबॉर्ट परीक्षण स्थानीय रहता है और इसे सीआई में हरी नहीं किया जाता है।

`pwsh -File .\verify.ps1 -Coverage`, `src/Watchdog` के लिए लाइन कवरेज जोड़ता है और यदि कवरेज 90% से कम है, तो यह विफल हो जाता है। सीआई (CI) इसे उसी तरह से चलाता है और रिपोर्ट को कोडकोव (Codecov) पर अपलोड करता है, जिसके लिए पूरे मॉड्यूल और प्रत्येक परिवर्तन के लिए कम से कम 90% कवरेज की आवश्यकता होती है।

## उत्पत्ति

यह पहले से ही 5090 पर चल रहे वॉचडॉग का एक निष्कर्षण है। पूर्व-निष्कर्षण स्क्रिप्ट [`origin/`](origin/) के अंतर्गत SHA-256 पिन के साथ जमा हैं। दिनांकित घटनाएं (पार्स क्रैश, पांच सप्ताह का अंतराल, असुरक्षित ai-toolkit, 153 खाली ABORT, एक-नमूना मृत्यु) [docs/incidents.md](docs/incidents.md) में हैं।

## लाइसेंस

MIT. [LICENSE](LICENSE) देखें। समर्थित: 1.x.

[MCP टूल शॉप](https://mcp-tool-shop.github.io/) द्वारा निर्मित।
