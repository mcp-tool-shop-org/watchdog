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

# watchdog

**विंडोज पर लंबे GPU कार्यों के लिए एक सख्त सीमा।** watchdog आपके NVIDIA कार्ड के VRAM और तापमान, और आपके सिस्टम RAM की हर 2 सेकंड में जांच करता है। जब कोई सीमा लगातार तीन बार पार हो जाती है, तो यह उन पायथन इंटरप्रेटरों को बंद कर देता है जिन्हें आपने इसे बंद करने की अनुमति दी थी, और कुछ नहीं।

आप एक प्रशिक्षण सत्र या एक बड़ा रेंडर शुरू करते हैं, दूर चले जाते हैं, और एक मेमोरी लीक, बहुत बड़ी बैच या गर्म कार्ड इसे एक स्थिर डेस्कटॉप में बदल देता है। watchdog वह छोटा प्रोसेस है जो आपके लिए जागता रहता है: यह उन सीमाओं को लागू करता है जिन्हें आपने सेट किया है, यह रिकॉर्ड करता है कि इसने क्या देखा, और यह आपको स्पष्ट रूप से बताता है कि यह आपको कब सुरक्षित नहीं रख सका।

## आपको क्या मिलता है

- **आपके द्वारा चुनी गई सीमाएं।** VRAM MiB में, RAM प्रतिशत में, GPU तापमान °C में। कोई छिपी हुई डिफ़ॉल्ट सेटिंग नहीं है।
- **लक्षित स्टॉप।** केवल उन इंटरप्रेटर पथों को बंद किया जा सकता है जिन्हें आपने सूचीबद्ध किया है (साथ ही एक वैकल्पिक WSL प्रक्रिया पैटर्न)। मशीन पर अन्य सभी पायथन प्रक्रियाओं को अकेला छोड़ दिया जाता है।
- **कोई झूठा आराम नहीं।** आपके द्वारा सूचीबद्ध प्रक्रियाओं में से किसी से भी मेल न खाने वाली उल्लंघन को एक सुरक्षा अंतराल के रूप में लिखा जाता है, और VRAM को होल्ड करने वाली प्रक्रियाओं का नाम दिया जाता है।
- **watchdog के लिए एक watchdog।** एक वैकल्पिक अनुसूचित कार्य हर मिनट में एक बार हार्टबीट की जांच करता है और यदि यह बंद हो जाता है तो बाहर से watchdog को मृत घोषित कर देता है। यह कभी भी अपने आप कुछ भी पुनरारंभ नहीं करता है।
- **स्पष्ट जीवितता उत्तर।** `watchdog status` 0 (चल रहा है), 1 (नहीं चल रहा है) या 2 (पूरी तरह से बंद) के रूप में बाहर निकलता है।
- **प्रत्येक रन का रिकॉर्ड।** नमूनों की एक CSV, एक किल लॉग, एक कंसोल ट्रांसक्रिप्ट और एक क्रैश लॉग, ये सभी एक फ़ोल्डर के तहत रखे जाते हैं जिसे आप चुनते हैं।
- **वैकल्पिक WSL मेमोरी रिटर्न।** यदि WSL की फ़ाइल कैश विंडोज मेमोरी को भर देती है, तो पोलर उस कैश को छोड़ सकता है। यह कभी भी किसी प्रक्रिया को नहीं रोकता है और न ही किसी बंद डिस्ट्रो को शुरू करता है।

## त्वरित शुरुआत

आवश्यकताएं: विंडोज, PowerShell 7.1 या नया, और `PATH` पर `nvidia-smi` के साथ एक NVIDIA ड्राइवर।

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` आपकी सहमति है: इसके बिना या कॉन्फ़िगरेशन में `AllowKill = $true` के बिना watchdog शुरू नहीं होगा। इसे एक मॉड्यूल के रूप में स्थापित करने और बाहरी जांच जोड़ने के लिए:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## यह कैसे काम करता है

1. **नमूना।** हर `IntervalSec` (डिफ़ॉल्ट रूप से 2 सेकंड) यह `nvidia-smi` से GPU तापमान, शक्ति और VRAM, और विंडोज से सिस्टम RAM पढ़ता है।
2. **किसी पैटर्न का इंतजार करें, किसी अचानक वृद्धि का नहीं।** किसी भी चीज़ के होने से पहले एक सीमा को लगातार `BreachSamples` बार (डिफ़ॉल्ट रूप से 3) पार करना होगा। चेतावनी के संदेश रास्ते में लॉग किए जाते हैं।
3. **केवल वही बंद करें जिसे आपने सूचीबद्ध किया है।** लगातार उल्लंघन होने पर यह उन `python` प्रक्रियाओं को बंद कर देता है जिनके पथ `Targets` में हैं, और वैकल्पिक WSL `pkill` पैटर्न चलाता है। यह रिकॉर्ड करता है कि इसने क्या बंद किया, या यह कि इसने कुछ भी बंद नहीं किया।
4. **यह साबित करें कि यह जीवित है।** लूप हर नमूने में एक हार्टबीट फ़ाइल को फिर से लिखता है। `watchdog status` और अनुसूचित पोलर उस हार्टबीट से जीवितता का आकलन करते हैं, इसलिए एक मृत watchdog कभी भी स्वस्थ नहीं दिख सकता है।

## कमांड

| कमांड | यह क्या करता है |
|---|---|
| `watchdog status` | जीवितता जांच। 0 (चल रहा है), 1 (नहीं चल रहा है), 2 (पूरी तरह से बंद) के रूप में बाहर निकलें। |
| `watchdog start -AllowKill` | किसी भी पुराने लूप को साफ-सुथरा तरीके से बंद कर देता है, पृष्ठभूमि में एक नया शुरू करता है, और इसके हार्टबीट का इंतजार करता है। |
| `watchdog stop` | लूप को एक सेंटिनल फ़ाइल के माध्यम से बंद करने के लिए कहता है और इसका इंतजार करता है। |
| `watchdog poll` | एक बाहरी जांच, जैसा कि अनुसूचित कार्य द्वारा चलाया जाता है। |
| `watchdog install` / `uninstall` | मॉड्यूल को कॉपी या हटाएं। `install -Poll` अनुसूचित जांच को भी पंजीकृत करता है। |
| `watchdog help` / `version` | फ्लैग, निकास कोड और संस्करण। |

`start` VRAM पहले से ही आपकी सीमा से अधिक होने पर 3 के साथ अस्वीकार कर देता है (केवल तभी `-Force` का उपयोग करें जब आपका मतलब हो)। `status -Hook` एक क्लाउड कोड SessionStart संदेश प्रिंट करता है और हमेशा 0 के साथ बाहर निकलता है, इसलिए एक मृत watchdog को सत्र को बाधित किए बिना रिपोर्ट किया जाता है। पूर्ण संदर्भ: [हैंडबुक → संदर्भ](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/)।

## कॉन्फ़िगरेशन

watchdog बिना कॉन्फ़िगरेशन के शुरू नहीं होगा। यह `-ConfigPath`, फिर `$env:WATCHDOG_CONFIG`, फिर `./watchdog.config.psd1`, फिर `~/.watchdog/config.psd1` में देखता है।

| आवश्यक | अर्थ |
|---|---|
| `Root` | हार्टबीट, लॉग और सेंटिनल के लिए पूर्ण फ़ोल्डर। watchdog कहीं और नहीं लिखता है। |
| `Targets` | पूर्ण इंटरप्रेटर पथ जिन्हें यह बंद कर सकता है। |
| `VramKillMiB` | MiB में VRAM सीमा। 32 GB कार्ड के लिए, `31200` लगभग 1.4 GB का हेडरूम छोड़ देता है। |
| `RamKillPct` | सिस्टम RAM सीमा प्रतिशत में। |
| `TempKillC` | GPU तापमान सीमा °C में। |

यदि कोई कार्य सामान्य उपयोग में VRAM सीमा को ट्रिगर करता है, तो कार्य को सीमित करें (ComfyUI, `--reserve-vram` के लिए) बजाय इसके कि सीमा को बढ़ाया जाए। अन्य सभी सेटिंग्स, जिसमें WSL कैश रिलीज़ भी शामिल है, [हैंडबुक → कॉन्फ़िगरेशन](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/) में हैं।

## सुरक्षा

- **सबसे पहले सहमति।** `-AllowKill` या `AllowKill = $true` के बिना कुछ भी कभी बंद नहीं किया जाता है।
- **स्पर्श किया गया:** `Root` के तहत फ़ाइलें, प्रक्रिया सूची, GPU काउंटर; और, यदि आप उन्हें सक्षम करते हैं, तो एक WSL `pkill` पैटर्न और WSL पेज-कैश ड्रॉप।
- **स्पर्श नहीं किया गया:** आपके स्रोत ट्री, चेकपॉइंट, क्रेडेंशियल और नेटवर्क। कोई टेलीमेट्री मशीन नहीं छोड़ती है।
- **एकल अपरिवर्तनीय कार्रवाई स्वयं स्टॉप है।** एक बंद किए गए कार्य में जो कुछ भी सहेजा नहीं गया है, वह खो जाता है। क्या खो गया है, और इसे कैसे पुनर्प्राप्त किया जाए, यह [docs/compensators.md](docs/compensators.md) में है।

किसी भेद्यता की रिपोर्ट करने के लिए [SECURITY.md](SECURITY.md) देखें।

## प्लेटफ़ॉर्म

संस्करण 1 केवल विंडोज के लिए है: यह PowerShell 7, `nvidia-smi`, विंडोज GPU प्रक्रिया-मेमोरी काउंटर और, वैकल्पिक रूप से, WSL पर निर्भर करता है। लिनक्स समर्थन बाद के संस्करण के लिए योजनाबद्ध है।

## विकास

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

परीक्षणों में प्रत्येक स्टॉप, लॉन्च और अनुसूचित-कार्य कॉल को मॉक किया जाता है, इसलिए उन्हें चलाने से कभी भी वास्तविक प्रक्रियाएं प्रभावित नहीं होती हैं। प्री-एक्सट्रैक्शन स्क्रिप्ट को [`origin/`](origin/) के तहत रखा जाता है, हैश-पिन किया जाता है, और उन घटनाओं को [docs/incidents.md](docs/incidents.md) में वर्णित किया गया है जिन्होंने डिज़ाइन को आकार दिया।

## लाइसेंस

MIT. [LICENSE](LICENSE) देखें।

[MCP टूल शॉप](https://mcp-tool-shop.github.io/) द्वारा निर्मित।
