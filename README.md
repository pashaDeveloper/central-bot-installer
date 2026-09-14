> Shared installer: 1 Install admin bot; 2 Install customer bot; 3 Manage admin bot; 4 Manage customer bot. Management submenu: 1 Settings; 2 Update; 3 Remove. Customer source: https://github.com/pashaDeveloper/customer-bot; installation: `/opt/customer-bot`. This replaces the old menu numbering below.

# Central Bot installer

نصاب عمومی برای دریافت و نصب سورس خصوصی Central Bot روی Ubuntu و Debian دارای systemd.

```bash
curl -fsSL https://raw.githubusercontent.com/pashaDeveloper/central-bot-installer/main/install.sh -o /tmp/central-bot-install.sh && sudo bash /tmp/central-bot-install.sh
```

ابتدا منوی زیر نمایش داده می‌شود؛ پیش از انتخاب شما هیچ نصب یا دریافت سورسی انجام نمی‌شود:

```text
1. Install
2. Edit
3. Remove
4. Update from GitHub
q) Exit
```

گزینهٔ ۲ تنظیمات ربات نصب‌شده را باز می‌کند. گزینهٔ ۳ پس از تأیید `REMOVE` کانتینر و فایل‌های ربات را حذف می‌کند؛ دیتابیس آنلاین، Cloudinary، کلید GitHub و پشتیبان‌های محلی حفظ می‌شوند. گزینهٔ ۴ ابتدا از سورس و تنظیمات پشتیبان می‌گیرد، سپس سورس جدید GitHub را دریافت و با حفظ `.env` دوباره build و اجرا می‌کند.

مراحل گزینهٔ ۱:

1. `apt-get update` و `apt-get upgrade -y` اجرا و پیش‌نیازها و Docker نصب می‌شوند.
2. مخزن `git@github.com:pashaDeveloper/central-bot.git`، شاخهٔ `main` و مسیر ریشهٔ مخزن خودکار انتخاب می‌شوند و پرسیده نمی‌شوند.
3. نصاب یک کلید SSH اختصاصی می‌سازد و فقط کلید عمومی را نمایش می‌دهد.
4. کلید عمومی را در [Deploy keys مخزن خصوصی](https://github.com/pashaDeveloper/central-bot/settings/keys) با **Add deploy key** ثبت کنید. گزینهٔ **Allow write access** خاموش بماند. سپس در ترمینال Enter بزنید.
5. سورس خصوصی دانلود می‌شود؛ اطلاعات تلگرام، MongoDB و Cloudinary پرسیده و ربات اجرا می‌شود.

فایل‌های برنامه در `/opt/central-bot`، تنظیمات در `/opt/central-bot/.env` و کلید خصوصی فقط روی سرور در `/etc/central-bot-installer/deploy_key` نگهداری می‌شوند. در اجرای مجدد همان کلید استفاده می‌شود.

در نصب جدید، IP عمومی سرور خودکار تشخیص داده می‌شود و آدرس ربات `http://IP:3000` است؛ پورت TCP ۳۰۰۰ باید از بیرون قابل دسترسی باشد. اتصال خروجی SSH به GitHub روی پورت ۲۲ لازم است. سورس برنامه، تنظیمات واقعی، دیتابیس و کلیدهای خصوصی در این مخزن عمومی قرار ندارند.
