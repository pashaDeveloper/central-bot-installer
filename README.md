# Central Bot installer

نصاب عمومی برای دریافت و نصب سورس خصوصی Central Bot روی Ubuntu و Debian دارای systemd.

```bash
curl -fsSL https://raw.githubusercontent.com/pashaDeveloper/central-bot-installer/main/install.sh -o /tmp/central-bot-install.sh && sudo bash /tmp/central-bot-install.sh
```

1. ابتدا `apt-get update` و `apt-get upgrade -y` اجرا و پیش‌نیازها و Docker نصب می‌شوند.
2. برای مخزن، شاخه و مسیر ربات، Enter بزنید تا تنظیمات پیش‌فرض انتخاب شوند.
3. نصاب یک کلید SSH اختصاصی می‌سازد و فقط کلید عمومی را نمایش می‌دهد.
4. کلید عمومی را در [Deploy keys مخزن خصوصی](https://github.com/pashaDeveloper/central-bot/settings/keys) با **Add deploy key** ثبت کنید. گزینهٔ **Allow write access** خاموش بماند. سپس در ترمینال Enter بزنید.
5. سورس خصوصی دانلود می‌شود؛ اطلاعات تلگرام، MongoDB و Cloudinary پرسیده و ربات اجرا می‌شود.

فایل‌های برنامه در `/opt/central-bot`، تنظیمات در `/opt/central-bot/.env` و کلید خصوصی فقط روی سرور در `/etc/central-bot-installer/deploy_key` نگهداری می‌شوند. در اجرای مجدد همان کلید استفاده می‌شود.

دامنه و پراکسی HTTPS باید به `127.0.0.1:3000` متصل شوند. اتصال خروجی SSH به GitHub روی پورت ۲۲ لازم است. سورس برنامه، تنظیمات واقعی، دیتابیس و کلیدهای خصوصی در این مخزن عمومی قرار ندارند.
