# License Selection Guide

Choosing the right license for your project is important. This guide helps you select between the three popular open-source licenses included in this template.

---

## Quick Decision Guide

### Choose **MIT License** if:
- ✅ You want maximum freedom for users
- ✅ You want minimal restrictions
- ✅ You don't need patent protection
- ✅ You're building a library or utility
- ✅ You want the simplest possible license

### Choose **Apache License 2.0** if:
- ✅ You want permissive licensing with patent protection
- ✅ You're building enterprise software
- ✅ You want users to credit changes
- ✅ You need explicit patent grant
- ✅ You want protection from patent trolls

### Choose **Mozilla Public License 2.0** if:
- ✅ You want file-level copyleft
- ✅ You want modified files to remain open source
- ✅ You want to allow proprietary combinations
- ✅ You want weaker copyleft than GPL
- ✅ You're building a library that may be used in commercial products

---

## Detailed Comparison

### Permission Summary

| Feature | MIT | Apache 2.0 | MPL 2.0 |
|---------|-----|------------|---------|
| **Commercial Use** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Modification** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Distribution** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Private Use** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Patent Grant** | ❌ No | ✅ Yes | ✅ Yes (limited) |
| **Sublicensing** | ✅ Yes | ✅ Yes | ⚠️ Limited |
| **Copyleft** | ❌ None | ❌ None | ⚠️ File-level |
| **License Compatibility** | ✅ High | ✅ High | ⚠️ Medium |

### Requirement Summary

| Requirement | MIT | Apache 2.0 | MPL 2.0 |
|------------|-----|------------|---------|
| **Include License** | ✅ Required | ✅ Required | ✅ Required |
| **Include Copyright** | ✅ Required | ✅ Required | ✅ Required |
| **State Changes** | ❌ No | ✅ Required | ✅ Required |
| **Disclose Source** | ❌ No | ❌ No | ⚠️ Modified files only |
| **Same License** | ❌ No | ❌ No | ⚠️ Modified files only |
| **Trademark Use** | ❌ Not granted | ❌ Not granted | ❌ Not granted |
| **Liability** | ❌ None | ❌ None | ❌ None |
| **Warranty** | ❌ None | ❌ None | ❌ None |

---

## License Details

### 1. MIT License

**Summary:** The most permissive and simple license. Anyone can do almost anything with your code.

**Length:** ~170 words (very short)

**Pros:**
- ✅ Very simple and easy to understand
- ✅ Maximum freedom for users
- ✅ Widely recognized and trusted
- ✅ Compatible with almost all other licenses
- ✅ No "copyleft" requirements
- ✅ Can be sublicensed under different terms
- ✅ Business-friendly

**Cons:**
- ❌ No patent grant (potential patent issues)
- ❌ No protection from patent trolls
- ❌ Doesn't require attribution in binaries
- ❌ No requirement to state changes
- ❌ Code can be taken private

**Best For:**
- Libraries and frameworks
- Utilities and tools
- Educational projects
- Projects where you want maximum adoption

**Popular Projects Using MIT:**
- jQuery
- Rails
- .NET Core
- Node.js
- React

**Key Requirements:**
1. Include original copyright notice
2. Include license text

**That's it!** Very minimal requirements.

---

### 2. Apache License 2.0

**Summary:** Permissive license with explicit patent grant and requirement to state changes.

**Length:** ~8,800 words (comprehensive)

**Pros:**
- ✅ Explicit patent grant protects users
- ✅ Includes patent retaliation clause
- ✅ Requires stating changes to code
- ✅ Well-understood by corporations
- ✅ Compatible with GPL 3.0
- ✅ Trusted for enterprise use
- ✅ Can be sublicensed

**Cons:**
- ❌ Longer and more complex than MIT
- ❌ Requires NOTICE file for attributions
- ❌ Requires stating changes
- ❌ More paperwork for contributors
- ❌ Incompatible with GPL 2.0

**Best For:**
- Enterprise software
- Projects where patents are a concern
- Large projects with many contributors
- Projects needing patent protection

**Popular Projects Using Apache 2.0:**
- Android
- Apache projects (Kafka, Spark, etc.)
- Kubernetes
- TensorFlow
- Swift

**Key Requirements:**
1. Include original copyright notice
2. Include license text
3. State significant changes made
4. Include NOTICE file if present
5. Don't use trademarks without permission

---

### 3. Mozilla Public License 2.0 (MPL 2.0)

**Summary:** Weak copyleft license - modified files must remain open, but can be combined with proprietary code.

**Length:** ~4,700 words (medium)

**Pros:**
- ✅ File-level copyleft (weaker than GPL)
- ✅ Can be combined with proprietary code
- ✅ Includes patent grant
- ✅ Compatible with GPL and LGPL
- ✅ Requires sharing modifications
- ✅ Business-friendly copyleft option

**Cons:**
- ❌ More complex than MIT/Apache
- ❌ Modified files must stay open source
- ❌ Requires separate file organization
- ❌ Less common than MIT/Apache
- ❌ Can complicate commercial use

**Best For:**
- Libraries used in commercial products
- Projects wanting some copyleft protection
- Mozilla-style projects
- When you want modifications shared but allow proprietary combinations

**Popular Projects Using MPL 2.0:**
- Firefox
- Thunderbird
- LibreOffice
- This template repository

**Key Requirements:**
1. Include original license notice
2. Keep modified MPL files under MPL
3. Disclose source of modified MPL files
4. Can combine with proprietary code in separate files
5. State changes to MPL files

**File-Level Copyleft Explained:**
- ✅ Can add proprietary files to project
- ✅ Can link with proprietary libraries
- ⚠️ Modified MPL files must remain MPL
- ⚠️ Must share source of modified MPL files

---

## Decision Tree

```
Start Here
│
├─ Do you want modified code to remain open source?
│  ├─ Yes → **Consider MPL 2.0**
│  │  └─ But only for modified files? → **MPL 2.0**
│  └─ No → Continue...
│
├─ Is patent protection important?
│  ├─ Very important → **Apache 2.0**
│  │  └─ Enterprise software? → **Apache 2.0**
│  └─ Not critical → Continue...
│
├─ Do you want the simplest possible license?
│  ├─ Yes → **MIT**
│  │  └─ Maximum freedom? → **MIT**
│  └─ No → **Apache 2.0** (safer than MIT)
│
└─ When in doubt → **MIT** (most popular)
```

---

## Real-World Examples

### Scenario 1: JavaScript Library
**Project:** React-style UI framework

**Recommendation:** **MIT**

**Why:**
- Maximum adoption in ecosystem
- Compatible with all build tools
- No patent concerns in JS ecosystem
- Simple for contributors

---

### Scenario 2: Enterprise API Server
**Project:** REST API server for financial data

**Recommendation:** **Apache 2.0**

**Why:**
- Patent protection for API methods
- Corporate-friendly
- Protects against patent trolls
- Clear change tracking

---

### Scenario 3: .NET Class Library
**Project:** Extension methods library

**Recommendation:** **MIT** or **Apache 2.0**

**Why:**
- **MIT:** If you want maximum adoption
- **Apache 2.0:** If you have novel algorithms needing patent protection

---

### Scenario 4: Desktop Application
**Project:** Open-source code editor

**Recommendation:** **MPL 2.0**

**Why:**
- Ensures improvements stay open
- Allows proprietary plugins
- File-level copyleft is reasonable
- Similar to VS Code approach (though VS Code uses MIT)

---

## License Compatibility

### Can you combine licenses in one project?

**MIT + Apache 2.0:** ✅ Yes  
**MIT + MPL 2.0:** ✅ Yes  
**Apache 2.0 + MPL 2.0:** ✅ Yes  
**GPL 2.0 + Apache 2.0:** ❌ No (incompatible)  
**GPL 3.0 + Apache 2.0:** ✅ Yes

### Using libraries with different licenses:

| Your License | Can use MIT libs? | Can use Apache 2.0 libs? | Can use MPL 2.0 libs? |
|--------------|-------------------|--------------------------|----------------------|
| **MIT** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Apache 2.0** | ✅ Yes | ✅ Yes | ✅ Yes |
| **MPL 2.0** | ✅ Yes | ✅ Yes | ✅ Yes |

**Note:** You can use more permissive libraries in less permissive projects, but not vice versa.

---

## Setup Instructions

### Using the Automated Setup Script

The setup scripts will prompt you to choose a license:

```bash
# PowerShell
pwsh ./scripts/setup.ps1

# Bash
./scripts/setup.sh
```

You'll be asked:
```
Select a license:
1) MIT
2) Apache-2.0
3) MPL-2.0
```

The script will:
1. Copy the chosen license template
2. Replace `{{YEAR}}` with the current year
3. Replace `{{COPYRIGHT_HOLDER}}` with your name
4. Save as `LICENSE` (no extension)
5. Delete all `LICENSE-*.txt` files

### Manual Setup

1. Choose a license from above
2. Copy the corresponding file:
   - `LICENSE-MIT.txt` → `LICENSE`
   - `LICENSE-APACHE-2.0.txt` → `LICENSE`
   - `LICENSE-MPL-2.0.txt` → `LICENSE`
3. Replace placeholders:
   - `{{YEAR}}` → Current year (e.g., `2024`)
   - `{{COPYRIGHT_HOLDER}}` → Your name (e.g., `Chris Wolfgang`)
4. Update `README.md`:
   - Replace `{{LICENSE_TYPE}}` with `MIT`, `Apache-2.0`, or `MPL-2.0`
5. Delete unused `LICENSE-*.txt` files

---

## Frequently Asked Questions

### Q: Can I change the license later?

**A:** Yes, but:
- Previous versions remain under the old license
- Requires all contributors to agree if not sole copyright holder
- May complicate things for existing users

### Q: What if I want dual licensing?

**A:** This template supports single license only. For dual licensing:
1. Keep both LICENSE files
2. Add explanation in README
3. Specify in headers which applies

### Q: What about the Unlicense or CC0?

**A:** These are public domain dedications, not licenses. Not included in this template as they're not recommended for software.

### Q: What about GPL?

**A:** GPL is not included because:
- Strong copyleft can limit adoption
- Not ideal for libraries
- More complex for contributors
- This template targets permissive licenses

If you need GPL, use GPL templates specifically.

---

## Additional Resources

### Official License Texts
- **MIT:** https://opensource.org/licenses/MIT
- **Apache 2.0:** https://www.apache.org/licenses/LICENSE-2.0
- **MPL 2.0:** https://www.mozilla.org/en-US/MPL/2.0/

### License Choosers
- **GitHub:** https://choosealicense.com/
- **OSI:** https://opensource.org/licenses/

### Legal Resources
- **SPDX License List:** https://spdx.org/licenses/
- **TLDRLegal:** https://www.tldrlegal.com/

**Disclaimer:** This guide is for informational purposes only and does not constitute legal advice. Consult a lawyer for specific legal questions.

---

## Quick Reference

| Aspect | MIT | Apache 2.0 | MPL 2.0 |
|--------|-----|------------|---------|
| **Complexity** | ⭐ Simple | ⭐⭐⭐ Complex | ⭐⭐ Medium |
| **Length** | ⭐ Short | ⭐⭐⭐ Long | ⭐⭐ Medium |
| **Permissive** | ⭐⭐⭐ Very | ⭐⭐⭐ Very | ⭐⭐ Moderate |
| **Patent Protection** | ❌ None | ⭐⭐⭐ Strong | ⭐⭐ Moderate |
| **Business Friendly** | ⭐⭐⭐ Very | ⭐⭐⭐ Very | ⭐⭐ Moderate |
| **Popularity** | ⭐⭐⭐ Very high | ⭐⭐⭐ High | ⭐⭐ Medium |

---

**Still unsure?** Choose **MIT** - it's the most popular and simplest option. You can always change it later (with caveats).
