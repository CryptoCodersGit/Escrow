# Crypto Coders | Solidity Escrow Payment System

قرارداد هوشمند سیستم پرداخت امانی (Escrow) به زبان Solidity بین کارفرما، مجری و داور سوم‌شخص با قابلیت مدیریت اختلاف و مهلت زمانی.

## ساختار فایل‌ها و قرارداد

| فایل | نام قرارداد | نسخه کامپایلر | توضیحات |
|---|---|---|---|
| `EscrowSystemPayment.sol` | `EscrowSystemPayment` | `^0.8.24` | نگهداری امن وجه توافق، آزادسازی با تأیید کارفرما، داوری اختلافات و استرداد پس از ددلاین |

## نقش‌ها و وضعیت‌ها
- **نقش‌ها:** `client` (کارفرما/پرداخت‌کننده)، `customer` (مجری/دریافت‌کننده) و `refree` (داور مرضی‌الطرفین)
- **وضعیت‌ها (`enum Status`):** `AwaitingPayment`، `Funded`، `Completed`، `Refunded` و `Disputed`

## توابع اصلی
- `constructor(...)`: تنظیم آدرس طرفین (`client`، `customer`، `refree`)، مبلغ دقیق (`paymentAmount`)، مهلت زمانی (`deadline`)، توضیحات و شرایط
- `deposit() payable`: واریز دقیق مبلغ قرارداد توسط کارفرما (`onlyClient`) و تغییر وضعیت به `Funded`
- `approveWork()`: تأیید انجام کار توسط کارفرما (`onlyClient`) و انتقال وجه قفل‌شده به `customer`
- `raiseDispute()`: ثبت درخواست داوری توسط کارفرما یا مجری و تغییر وضعیت به `Disputed`
- `resolveDispute(bool releaseToCustomer)`: رأی نهایی داور (`onlyRefree`) برای آزادسازی وجه به مجری یا استرداد آن به کارفرما
- `refundAfterDeadline()`: استرداد وجه به کارفرما توسط داور در صورت عبور از مهلت زمانی (`deadline`)
- `getEscrowedAmount()` و `getBalance()`: مشاهده موجودی قفل‌شده در قرارداد
