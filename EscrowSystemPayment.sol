
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EscrowSystemPayment
 * @author Crypto Coders
 * @notice قرارداد امانی برای نگهداری ETH تا زمان تأیید انجام کار
 * @dev Ali Babaki
 * سناریو:
 * 1. client قرارداد را ایجاد می‌کند.
 * 2. client مبلغ توافق‌شده را به قرارداد واریز می‌کند.
 * 3. پس از تأیید کار، مبلغ به customer پرداخت می‌شود.
 * 4. در صورت اختلاف، refree درباره پرداخت یا بازپرداخت تصمیم می‌گیرد.
 */
contract EscrowSystemPayment {

    // ---------------------------------------------------------
    // 1. وضعیت‌های ممکن قرارداد
    // ---------------------------------------------------------

    /**
     * AwaitingPayment: منتظر واریز مبلغ از طرف client
     * Funded: مبلغ توافق‌شده در قرارداد قرار گرفته است
     * Completed: پرداخت به customer انجام شده است
     * Refunded: مبلغ به client بازگردانده شده است
     * Disputed: یکی از طرفین اختلاف را ثبت کرده است
     */
    enum Status {
        AwaitingPayment,
        Funded,
        Completed,
        Refunded,
        Disputed
    }

    // ---------------------------------------------------------
    // 2. اطلاعات طرفین معامله
    // ---------------------------------------------------------

    // شخصی که قرارداد را ایجاد می‌کند و هزینه را می‌پردازد.
    address public immutable client;

    // شخصی که کار را انجام می‌دهد و وجه را دریافت می‌کند.
    address payable public immutable customer;

    // داور مورد اعتماد برای حل اختلاف میان طرفین.
    address public immutable refree;

    // ---------------------------------------------------------
    // 3. اطلاعات توافق
    // ---------------------------------------------------------

    // مبلغ توافق‌شده برحسب wei.
    // برای مثال، 1 ETH برابر با 1e18 wei است.
    uint256 public immutable paymentAmount;

    // مهلت توافق برحسب Unix timestamp و ثانیه.
    uint256 public immutable deadline;

    // شرح کاری که باید انجام شود.
    // این مقدار روی بلاکچین عمومی قابل مشاهده خواهد بود.
    string public description;

    // شرایط توافق میان client و customer.
    // این مقدار نیز عمومی است و نباید اطلاعات محرمانه داشته باشد.
    string public terms;

    // وضعیت فعلی معامله.
    Status public status;

    // مبلغی که از طریق تابع fund برای این معامله تأمین شده است.
    // مبنای پرداخت‌ها این متغیر است، نه کل موجودی قرارداد.
    uint256 public escrowedAmount;

    // وضعیت قفل برای جلوگیری از فراخوانی بازگشتی توابع حساس.
    uint256 private _lock = 1;

    // ---------------------------------------------------------
    // 4. رویدادها (Events)
    // ---------------------------------------------------------

    // هنگام واریز موفق مبلغ توافق‌شده منتشر می‌شود.
    event PaymentFunded(address indexed client, uint256 amount);

    // وقتی client انجام کار را تأیید می‌کند.
    event WorkApproved(address indexed client);

    // پس از پرداخت وجه به customer.
    event PaymentReleased(address indexed customer, uint256 amount);

    // پس از بازگرداندن وجه به client.
    event PaymentRefunded(address indexed client, uint256 amount);

    // هنگامی که یکی از طرفین اختلاف را ثبت می‌کند.
    event DisputeRaised(address indexed raisedBy);

    // پس از تعیین نتیجه اختلاف توسط داور.
    event DisputeResolved(Status resolution);

    // ---------------------------------------------------------
    // 5. خطاهای سفارشی (Custom Errors)
    // ---------------------------------------------------------

    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDeadline();
    error IncorrectPayment();
    error InvalidStatus();
    error DeadlineNotReached();
    error TransferFailed();
    error SameParty();
    error ReentrantCall();

    // ---------------------------------------------------------
    // 6. Modifierها
    // ---------------------------------------------------------

    /**
     * فقط client اجازه اجرای تابع را دارد.
     * msg.sender آدرس کسی است که تراکنش را ارسال کرده است.
     */
    modifier onlyClient() {
        if (msg.sender != client) revert Unauthorized();
        _;
    }

    /**
     * فقط داور اجازه اجرای تابع را دارد.
     */
    modifier onlyRefree() {
        if (msg.sender != refree) revert Unauthorized();
        _;
    }

    /**
     * تابع فقط در وضعیت مشخص‌شده قابل اجرا است.
     * برای مثال، پرداخت فقط زمانی مجاز است که قرارداد Funded باشد.
     */
    modifier inStatus(Status expected) {
        if (status != expected) revert InvalidStatus();
        _;
    }

    /**
     * محافظ ساده در برابر Reentrancy.
     * اگر تابع حساس در حین اجرای خود دوباره فراخوانی شود،
     * اجرای مجدد متوقف خواهد شد.
     */
    modifier nonReentrant() {
        if (_lock != 1) revert ReentrantCall();

        _lock = 2;
        _;
        _lock = 1;
    }

    // ---------------------------------------------------------
    // 7. سازنده قرارداد (Constructor)
    // ---------------------------------------------------------

    /**
     * @param _customer آدرس دریافت‌کننده وجه
     * @param _refree آدرس داور اختلاف
     * @param _paymentAmount مبلغ توافق‌شده برحسب wei
     * @param _deadline مهلت معامله به‌صورت Unix timestamp
     * @param _description شرح پروژه یا خدمت
     * @param _terms شرایط توافق
     *
     * سازنده هنگام Deploy فقط یک بار اجرا می‌شود.
     * client همان آدرسی است که قرارداد را Deploy می‌کند.
     */
    constructor(
        address payable _customer,
        address _refree,
        uint256 _paymentAmount,
        uint256 _deadline,
        string memory _description,
        string memory _terms
    ) {
        // بررسی آدرس‌های نامعتبر.
        if (_customer == address(0) || _refree == address(0)) {
            revert InvalidAddress();
        }

        // برای ساده نگه‌داشتن ساختار، سه نقش باید متفاوت باشند.
        if (
            _customer == msg.sender ||
            _refree == msg.sender ||
            _customer == _refree
        ) {
            revert SameParty();
        }

        // مبلغ معامله باید بیشتر از صفر باشد.
        if (_paymentAmount == 0) {
            revert InvalidAmount();
        }

        // مهلت باید در آینده قرار داشته باشد.
        if (_deadline <= block.timestamp) {
            revert InvalidDeadline();
        }

        // ثبت طرفین معامله.
        client = msg.sender;
        customer = _customer;
        refree = _refree;

        // ثبت جزئیات توافق.
        paymentAmount = _paymentAmount;
        deadline = _deadline;
        description = _description;
        terms = _terms;

        // در شروع هنوز وجهی واریز نشده است.
        status = Status.AwaitingPayment;
    }

    // ---------------------------------------------------------
    // 8. واریز مبلغ توافق‌شده
    // ---------------------------------------------------------

    /**
     * فقط client می‌تواند مبلغ توافق‌شده را واریز کند.
     *
     * نکته:
     * مقدار ETH ارسال‌شده باید دقیقاً برابر paymentAmount باشد.
     * اگر مبلغ اشتباه باشد، کل تراکنش برگشت می‌خورد.
     */
    function fund()
        external
        payable
        onlyClient
        inStatus(Status.AwaitingPayment)
    {
        if (msg.value != paymentAmount) {
            revert IncorrectPayment();
        }

        // ثبت مبلغ متعلق به این معامله.
        escrowedAmount = msg.value;

        // تغییر وضعیت پس از دریافت وجه.
        status = Status.Funded;

        emit PaymentFunded(msg.sender, msg.value);
    }

    // ---------------------------------------------------------
    // 9. تأیید انجام کار و پرداخت به customer
    // ---------------------------------------------------------

    /**
     * client پس از رضایت از کار، این تابع را اجرا می‌کند.
     *
     * ترتیب عملیات:
     * 1. وضعیت و دسترسی بررسی می‌شود.
     * 2. وضعیت و مبلغ ثبت‌شده به‌روزرسانی می‌شوند.
     * 3. ETH به customer ارسال می‌شود.
     *
     * اگر انتقال ETH شکست بخورد، revert باعث می‌شود
     * تغییرات وضعیت و مبلغ نیز به حالت قبل برگردند.
     */
    function approveWork()
        external
        onlyClient
        inStatus(Status.Funded)
        nonReentrant
    {
        // مبلغ دقیق متعلق به معامله را ذخیره می‌کنیم.
        uint256 payment = escrowedAmount;

        // ثبت تغییرات قبل از فراخوانی آدرس خارجی.
        escrowedAmount = 0;
        status = Status.Completed;

        // ارسال وجه به customer.
        (bool success, ) = customer.call{value: payment}("");

        // در صورت شکست، همه تغییرات همین تراکنش برمی‌گردند.
        if (!success) revert TransferFailed();

        emit WorkApproved(msg.sender);
        emit PaymentReleased(customer, payment);
    }

    // ---------------------------------------------------------
    // 10. ثبت اختلاف
    // ---------------------------------------------------------

    /**
     * client یا customer می‌تواند اختلاف را ثبت کند.
     * پس از ثبت اختلاف، پرداخت عادی دیگر امکان‌پذیر نیست
     * و تصمیم‌گیری به داور واگذار می‌شود.
     */
    function raiseDispute()
        external
        inStatus(Status.Funded)
    {
        if (msg.sender != client && msg.sender != customer) {
            revert Unauthorized();
        }

        status = Status.Disputed;

        emit DisputeRaised(msg.sender);
    }

    // ---------------------------------------------------------
    // 11. تصمیم داور درباره اختلاف
    // ---------------------------------------------------------

    /**
     * @param payCustomer
     * true: پرداخت وجه به customer
     * false: بازگرداندن وجه به client
     *
     * فقط refree می‌تواند این تابع را اجرا کند
     * و فقط زمانی که وضعیت قرارداد Disputed باشد.
     */
    function resolveDispute(bool payCustomer)
        external
        onlyRefree
        inStatus(Status.Disputed)
        nonReentrant
    {
        uint256 payment = escrowedAmount;

        // مبلغ معامله پیش از ارسال وجه صفر می‌شود.
        escrowedAmount = 0;

        if (payCustomer) {
            // داور رأی داده است که customer وجه را دریافت کند.
            status = Status.Completed;

            (bool success, ) = customer.call{value: payment}("");
            if (!success) revert TransferFailed();

            emit PaymentReleased(customer, payment);
            emit DisputeResolved(Status.Completed);
        } else {
            // داور رأی داده است که مبلغ به client برگردد.
            status = Status.Refunded;

            (bool success, ) = payable(client).call{value: payment}("");
            if (!success) revert TransferFailed();

            emit PaymentRefunded(client, payment);
            emit DisputeResolved(Status.Refunded);
        }
    }

    // ---------------------------------------------------------
    // 12. بازپرداخت پس از پایان مهلت
    // ---------------------------------------------------------

    /**
     * اگر مهلت معامله تمام شود و قرارداد همچنان Funded باشد،
     * داور می‌تواند مبلغ را به client برگرداند.
     *
     * این تابع به‌صورت خودکار اجرا نمی‌شود؛
     * refree باید آن را فراخوانی کند.
     *
     * در این طراحی، پس از پایان مهلت امکان approveWork
     * همچنان وجود دارد؛ مگر اینکه اختلاف ثبت شود یا داور
     * بازپرداخت را انجام دهد. این یک تصمیم طراحی است.
     */
    function refundAfterDeadline()
        external
        onlyRefree
        inStatus(Status.Funded)
        nonReentrant
    {
        if (block.timestamp < deadline) {
            revert DeadlineNotReached();
        }

        uint256 payment = escrowedAmount;

        // ثبت وضعیت و صفرکردن مبلغ پیش از انتقال.
        escrowedAmount = 0;
        status = Status.Refunded;

        (bool success, ) = payable(client).call{value: payment}("");
        if (!success) revert TransferFailed();

        emit PaymentRefunded(client, payment);
    }

    // ---------------------------------------------------------
    // 13. مشاهده موجودی مربوط به معامله
    // ---------------------------------------------------------

    /**
     * موجودی ثبت‌شده برای معامله را برمی‌گرداند.
     * این مقدار با کل موجودی قرارداد یکسان نیست لزوماً؛
     * ممکن است ETH دیگری مستقیماً به قرارداد ارسال شده باشد.
     */
    function getEscrowedAmount() external view returns (uint256) {
        return escrowedAmount;
    }

    /**
     * کل موجودی ETH قرارداد را برمی‌گرداند.
     * این مقدار ممکن است از escrowedAmount بیشتر باشد.
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
