const lineTranslations = <String, (String, String)>{
  'نسبة الأمان بالكابتن: 100%': (
    'Captain safety indicator: 100%',
    'نیشاندەری سەلامەتی کاپتن: 100%',
  ),
  'نسبة الأمان بالكابتن: 0%': (
    'Captain safety indicator: 0%',
    'نیشاندەری سەلامەتی کاپتن: 0%',
  ),
  'النسبة مرتبطة بحالة الاشتراك فقط، وليست ضمانًا لسلامة الرحلة': (
    'This indicator reflects subscription status only and does not guarantee trip safety',
    'ئەم نیشاندەرە تەنها دۆخی بەشداری نیشان دەدات و گەرەنتی سەلامەتی گەشت نییە',
  ),

  'الكابتن غير مشترك بالتطبيق حاليًا': (
    'The captain is not currently subscribed',
    'کاپتن ئێستا بەشدار نییە',
  ),
  'حالة الاشتراك: فعّال • 100%': (
    'Subscription: active • 100%',
    'بەشداری: چالاک • 100%',
  ),
  'حالة الاشتراك: غير فعّال • 0%': (
    'Subscription: inactive • 0%',
    'بەشداری: ناچالاک • 0%',
  ),
  'جدّد اشتراكك لقبول خطوط جديدة': (
    'Renew your subscription to accept new routes',
    'بەشداریت نوێ بکەرەوە بۆ وەرگرتنی هێڵی نوێ',
  ),

  'حدد الانطلاق ثم الوصول ثم الرجوع لكل دوام': (
    'Set departure, arrival and return for each shift',
    'دەستپێک و گەیشتن و گەڕانەوە بۆ هەر دەوامێک دیاری بکە',
  ),
  'حدد كل يوم: صباحي أو ظهري أو عطلة': (
    'Assign each day to morning, afternoon or day off',
    'هەر ڕۆژێک بۆ بەیانی یان نیوەڕۆ یان پشوو دیاری بکە',
  ),
  'أيام العطلة': ('Days off', 'ڕۆژەکانی پشوو'),
  'الدوام الظهري': ('Afternoon shift', 'دەوامی نیوەڕۆ'),
  'الدوام الصباحي': ('Morning shift', 'دەوامی بەیانی'),
  'حدد الموقع على الخريطة': (
    'Choose a location on the map',
    'شوێن لەسەر نەخشە دیاری بکە',
  ),
  'البحث عن مكان': ('Search for a place', 'گەڕان بۆ شوێن'),
  'نوع ومسار الخط': ('Route type and path', 'جۆر و ڕێڕەوی هێڵ'),
  'مسار الخط': ('Route path', 'ڕێڕەوی هێڵ'),
  'مواعيد الخط': ('Route times', 'کاتەکانی هێڵ'),
  'الأجور والدفع': ('Fare and payment', 'کرێ و پارەدان'),
  'بيانات الراكب': ('Passenger details', 'زانیاری سەرنشین'),
  'مستمسكات الراكب': ('Passenger documents', 'بەڵگەنامەکانی سەرنشین'),
  'بيانات الزبون': ('Customer details', 'زانیاری کڕیار'),
  'وقت الوصول': ('Arrival time', 'کاتی گەیشتن'),
  'وقت الرجوع للمنزل': ('Return home time', 'کاتی گەڕانەوە بۆ ماڵەوە'),
  'كم تريد أن تدفع؟': (
    'How much would you like to pay?',
    'دەتەوێت چەند پارە بدەیت؟',
  ),
  'ما المبلغ الذي تفكر به؟': (
    'What amount do you have in mind?',
    'بیر لە چ بڕێک دەکەیتەوە؟',
  ),
  'عرض نقطة الانطلاق على الخريطة': (
    'View pickup on map',
    'بینینی شوێنی دەستپێک لەسەر نەخشە',
  ),
  'عرض نقطة الوصول على الخريطة': (
    'View destination on map',
    'بینینی شوێنی گەیشتن لەسەر نەخشە',
  ),
  'خريطة مسار الخط': ('Route map', 'نەخشەی هێڵ'),
  'تسجيل الخط': ('Register route', 'تۆمارکردنی هێڵ'),
  'غير محدد': ('Not specified', 'دیاری نەکراوە'),
  'حدد وقت الانطلاق والوصول والرجوع للمنزل': (
    'Choose departure, arrival and return home times',
    'کاتی دەستپێک و گەیشتن و گەڕانەوە بۆ ماڵ دیاری بکە',
  ),
  'أكمل نقطتي الخريطة وصور الجنسية، وحدد الانطلاق ثم الوصول ثم الرجوع للمنزل ويوم خدمة واحد على الأقل': (
    'Complete both map points and ID photos, choose departure then arrival then return home, and at least one service day',
    'دوو خاڵی نەخشە و وێنەی ناسنامە تەواو بکە، کاتی دەستپێک پاشان گەیشتن و گەڕانەوە دیاری بکە و لانیکەم یەک ڕۆژی خزمەتگوزاری',
  ),

  'يناير': ('January', 'کانوونی دووەم'),
  'فبراير': ('February', 'شوبات'),
  'مارس': ('March', 'ئازار'),
  'أبريل': ('April', 'نیسان'),
  'مايو': ('May', 'ئایار'),
  'يونيو': ('June', 'حوزەیران'),
  'يوليو': ('July', 'تەممووز'),
  'أغسطس': ('August', 'ئاب'),
  'سبتمبر': ('September', 'ئەیلوول'),
  'أكتوبر': ('October', 'تشرینی یەکەم'),
  'نوفمبر': ('November', 'تشرینی دووەم'),
  'ديسمبر': ('December', 'کانوونی یەکەم'),
  'الخطوط': ('Routes', 'هێڵەکان'),
  'خط مدرسة': ('School route', 'هێڵی قوتابخانە'),
  'خط عمل': ('Work route', 'هێڵی کار'),
  'خط التزام يومي': ('Daily route', 'هێڵی ڕۆژانە'),
  'خط يومي': ('Daily route', 'هێڵی ڕۆژانە'),
  'رحلات الخط': ('Route trips', 'گەشتەکانی هێڵ'),
  'رحلات زبائن': ('Customer trips', 'گەشتەکانی کڕیار'),
  'كل الرحلات': ('All trips', 'هەموو گەشتەکان'),
  'رحلة خط': ('Route trip', 'گەشتی هێڵ'),
  'تسجيل خط': ('Register a route', 'تۆمارکردنی هێڵ'),
  'نوع الخط': ('Route type', 'جۆری هێڵ'),
  'عندك طلاب وتريد تسويلهم خط للمدرسة؟': (
    'Need a school route for your children?',
    'قوتابیت هەیە و هێڵێکی قوتابخانەت دەوێت؟',
  ),
  'عندك التزام يومي وتريد خط؟ سجّل مسارك وحدد الأيام والوقت والسعر اللي يناسبك.': (
    'Need a daily route? Set your pickup, days, time and preferred total price.',
    'هێڵێکی ڕۆژانەت دەوێت؟ شوێن و ڕۆژ و کات و نرخی گونجاو دیاری بکە.',
  ),
  'سجّل الدخول من حسابي حتى تسجّل خط': (
    'Sign in through My account to register a route',
    'لە هەژمارەکەم بچۆ ژوورەوە بۆ تۆمارکردنی هێڵ',
  ),
  'ماكو خطوط حاليًا': ('No routes yet', 'هێشتا هێڵ نییە'),
  'من خطوطك': ('Your route', 'هێڵی تۆ'),
  'خط مقترح قريب': ('Nearby suggested route', 'هێڵی نزیک و پێشنیارکراو'),
  'اختَر خطك الأول، وبعدها نقترح خطوط قريبة منه.': (
    'Choose your first route to get nearby suggestions.',
    'یەکەم هێڵ هەڵبژێرە بۆ پێشنیاری هێڵە نزیکەکان.',
  ),
  'التزامك مكتمل؛ تختفي المقترحات لحد ما ينتهي أحد خطوطك.': (
    'You have 3 routes. Suggestions resume when a route ends.',
    '3 هێڵت هەیە؛ پێشنیارەکان دوای کۆتایی هێڵێک دەردەکەونەوە.',
  ),
  'حدد نقطة الانطلاق': ('Choose pickup point', 'شوێنی دەستپێک دیاری بکە'),
  'حدد نقطة الوصول': ('Choose destination', 'شوێنی گەیشتن دیاری بکە'),
  'حدد نقطة الانطلاق على الخريطة': (
    'Choose pickup on the map',
    'شوێنی دەستپێک لە نەخشە دیاری بکە',
  ),
  'حدد نقطة الوصول على الخريطة': (
    'Choose destination on the map',
    'شوێنی گەیشتن لە نەخشە دیاری بکە',
  ),
  'عدد أيام الخدمة': ('Service days', 'ژمارەی ڕۆژەکانی خزمەتگوزاری'),
  'تاريخ بداية الخط': ('Route start date', 'ڕێکەوتی دەستپێکی هێڵ'),
  'الأيام اللي ما يجي بيها الكابتن': (
    'Days the captain should not come',
    'ئەو ڕۆژانەی کاپتن نایەت',
  ),
  'الأيام المستبعدة ما تنخصم من عدد أيام الخدمة؛ تاريخ الانتهاء يتمدد تلقائيًا.': (
    'Excluded days do not count as service days. The end date extends automatically.',
    'ڕۆژە لابراوەکان لە ڕۆژەکانی خزمەتگوزاری ناژمێردرێن؛ ڕێکەوتی کۆتایی خۆکارانە درێژ دەبێتەوە.',
  ),
  'حدد السعر اللي يناسبك لكل مدة الخط': (
    'Your preferred price for the whole route term',
    'نرخی گونجاو بۆ تەواوی ماوەی هێڵ',
  ),
  'الدفع بنهاية مدة الخط، والسعر المعروض إجمالي كل الأيام.': (
    'Pay at the end. This is the total price for all service days.',
    'پارەدان لە کۆتایی ماوەکەیە؛ نرخەکە کۆی هەموو ڕۆژەکانە.',
  ),
  'وقت الانطلاق': ('Departure time', 'کاتی دەستپێک'),
  'يجب الوصول بالساعة': ('Must arrive by', 'دەبێت بگات تا'),
  'اسم الراكب الثلاثي': ('Passenger full name', 'ناوی تەواوی سەرنشین'),
  'اكتب الاسم الثلاثي': ('Enter the full name', 'ناوی تەواو بنووسە'),
  'صورة الجنسية — الوجه': ('ID photo — front', 'وێنەی ناسنامە — پێشەوە'),
  'صورة الجنسية — الخلف': ('ID photo — back', 'وێنەی ناسنامە — پشتەوە'),
  'تم التقاط وجه الجنسية': ('ID front captured', 'پێشەوەی ناسنامە وێنە کرا'),
  'تم التقاط خلف الجنسية': ('ID back captured', 'پشتەوەی ناسنامە وێنە کرا'),
  'صور الجنسية محفوظة للمراجعة الإدارية وما تظهر بالكارت أو بعروض الكباتن.': (
    'ID photos are private to administration and are not shown on route cards.',
    'وێنەکانی ناسنامە تایبەتن بە بەڕێوەبردن و لە کارتی هێڵ نیشان نادرێن.',
  ),
  'جاري التسجيل…': ('Registering…', 'تۆمار دەکرێت…'),
  'من 1 إلى 365 يوم': ('1 to 365 days', 'لە 1 تا 365 ڕۆژ'),
  'أدخل مبلغًا صحيحًا بالدينار': (
    'Enter a valid amount in IQD',
    'بڕێکی دروست بە دینار بنووسە',
  ),
  'اسمح للتطبيق باستخدام الكاميرا': (
    'Allow camera access',
    'ڕێگە بە بەکارهێنانی کامێرا بدە',
  ),
  'أكمل نقطتي الخريطة وصور الجنسية، وحدد وقت وصول بعد الانطلاق ويوم خدمة واحد على الأقل': (
    'Complete both map points and ID photos, choose arrival after departure and at least one service day',
    'هەردوو شوێن و وێنەکانی ناسنامە تەواو بکە؛ کاتی گەیشتن دوای دەستپێک و لانیکەم ڕۆژێک دیاری بکە',
  ),
  'تفاصيل الخط': ('Route details', 'وردەکاریی هێڵ'),
  'قبول الخط': ('Accept route', 'پەسەندکردنی هێڵ'),
  'إلغاء طلب الخط': ('Cancel route request', 'هەڵوەشاندنەوەی داوای هێڵ'),
  'تلتزم بمواعيد هذا الخط وأيامه. تكدر تقبل حتى 3 خطوط ولو بنفس الوقت. موافق؟': (
    'Commit to this route schedule? You may accept up to 3 routes, even at the same time.',
    'پابەند دەبیت بە کات و ڕۆژەکانی ئەم هێڵە؟ دەتوانیت تا 3 هێڵ پەسەند بکەیت تەنانەت لە هەمان کاتدا.',
  ),
  'الزبون': ('Customer', 'کڕیار'),
  'الراكب': ('Passenger', 'سەرنشین'),
  'الانطلاق': ('Pickup', 'دەستپێک'),
  'الوصول': ('Destination', 'گەیشتن'),
  'أيام الخدمة': ('Service days', 'ڕۆژەکانی خزمەتگوزاری'),
  'البداية': ('Start', 'دەستپێک'),
  'النهاية': ('End', 'کۆتایی'),
  'الأيام المستبعدة': ('Excluded days', 'ڕۆژە لابراوەکان'),
  'إجمالي الأجور': ('Total fare', 'کۆی کرێ'),
  'الدفع': ('Payment', 'پارەدان'),
  'يجب الوصول': ('Arrive by', 'بگات تا'),
  'هاتف الكابتن': ('Captain phone', 'ژمارەی کاپتن'),
  'جدول الخط': ('Route schedule', 'خشتەی هێڵ'),
  'التتبع المباشر': ('Live tracking', 'بەدواداچوونی ڕاستەوخۆ'),
  'الموقع يتحدث مباشرة': (
    'Location updating live',
    'شوێن ڕاستەوخۆ نوێ دەبێتەوە',
  ),
  'بانتظار مشاركة الموقع الحالي': (
    'Waiting for live location',
    'چاوەڕوانی شوێنی ڕاستەوخۆ',
  ),
  'مشاركة موقعي مع الكابتن وقت الخط': (
    'Share my location during the route',
    'هاوبەشکردنی شوێنم لە کاتی هێڵ',
  ),
  'موقعك يُشارك أثناء فتح تفاصيل الخط وقرب موعده': (
    'Location is shared while route details are open near its scheduled time',
    'شوێنت لە کاتی کردنەوەی وردەکاری و نزیک کاتی هێڵ هاوبەش دەکرێت',
  ),
  'تعذّر إرسال موقعك؛ تحقق من الاتصال': (
    'Unable to send location. Check your connection.',
    'نەتوانرا شوێن بنێردرێت؛ پەیوەندی بپشکنە.',
  ),
  'التوجّه لنقطة الانطلاق': ('Navigate to pickup', 'چوون بۆ دەستپێک'),
  'التوجّه لنقطة الوصول': ('Navigate to destination', 'چوون بۆ شوێنی گەیشتن'),
  'متوجه لاستلام الركاب': ('Heading to pickup', 'بەرەو وەرگرتنی سەرنشین'),
  'لقد وصلت': ('I have arrived', 'گەیشتم'),
  'بعد ركوب الراكب اختَر خطك التالي أو توجّه إلى الوجهة.': (
    'After boarding, choose the next route or go to the destination.',
    'دوای سواری سەرنشین، هێڵی دواتر یان شوێنی گەیشتن هەڵبژێرە.',
  ),
  'الخط التالي حان موعده': ('The next route is due', 'کاتی هێڵی دواتر هاتووە'),
  'انطلاق للخط التالي': ('Start the next route', 'دەستپێکی هێڵی دواتر'),
  'ذهاب إلى الوجهة': ('Go to destination', 'چوون بۆ شوێنی گەیشتن'),
  'ماكو خط قريب حان موعده؛ تكدر تتوجه إلى الوجهة.': (
    'No nearby route is due. Go to the destination.',
    'هیچ هێڵێکی نزیک کاتی نەهاتووە؛ بڕۆ بۆ شوێنی گەیشتن.',
  ),
  'الركاب وياك — وجهات الوصول': (
    'Passengers on board — destinations',
    'سەرنشینەکان — شوێنەکانی گەیشتن',
  ),
  'الذهاب لهذه الوجهة': ('Navigate here', 'چوون بۆ ئەم شوێنە'),
  'وصل الراكب إلى وجهته': ('Passenger delivered', 'سەرنشین گەیشتە شوێنەکەی'),
  'لقد استلمت الأموال': ('I received the payment', 'پارەکەم وەرگرت'),
  '✓ تم تأكيد استلام الأموال': (
    '✓ Payment receipt confirmed',
    '✓ وەرگرتنی پارە پشتڕاست کرایەوە',
  ),
  'سُجّل تحذير تأخير': (
    'Delay warning recorded',
    'ئاگاداریی دواکەوتن تۆمار کرا',
  ),
  'تفاصيل الخط والتتبع ←': (
    'Route details and tracking ←',
    'وردەکاری و بەدواداچوونی هێڵ ←',
  ),
  'ما عندك رحلات خط لحد اليوم.': (
    'No route trips up to today.',
    'تا ئەمڕۆ گەشتی هێڵت نییە.',
  ),
  'ما عندك رحلات زبائن بعد.': (
    'No customer trips yet.',
    'هێشتا گەشتی کڕیارت نییە.',
  ),
  'تعذّر تحديث رحلات الخط؛ اسحب للتحديث': (
    'Unable to load route trips. Pull to refresh.',
    'نەتوانرا گەشتەکان نوێ بکرێنەوە؛ ڕابکێشە بۆ نوێکردنەوە.',
  ),
  'بانتظار موافقة كابتن': (
    'Waiting for captain approval',
    'چاوەڕوانی پەسەندی کاپتن',
  ),
  'تم قبول الخط من قبل الكابتن': (
    'Route accepted by captain',
    'هێڵ لەلایەن کاپتن پەسەند کرا',
  ),
  'انتهت مدة الخط': ('Route term ended', 'ماوەی هێڵ کۆتایی هات'),
  'الخط ملغي': ('Route cancelled', 'هێڵ هەڵوەشایەوە'),
  'بانتظار الموعد': ('Waiting for scheduled time', 'چاوەڕوانی کاتی دیاریکراو'),
  'الكابتن متوجه لاستلام الركاب': (
    'Captain heading to pickup',
    'کاپتن بەرەو سەرنشینەکانە',
  ),
  'وصل الكابتن — بانتظار ركوب الراكب': (
    'Captain arrived — waiting for boarding',
    'کاپتن گەیشت — چاوەڕوانی سواری سەرنشین',
  ),
  'الركاب مع الكابتن': ('Passengers on board', 'سەرنشینەکان لەگەڵ کاپتنن'),
  'وصل الركاب': ('Passengers delivered', 'سەرنشینەکان گەیشتن'),
  'لم يُنفّذ': ('Not completed', 'جێبەجێ نەکرا'),
  'الدفع بنهاية مدة الخط': ('Payment at end of term', 'پارەدان لە کۆتایی ماوە'),
  'أجور الخط مستحقة': ('Route payment due', 'کرێی هێڵ دەبێت بدرێت'),
  'الزبون أكد الدفع؛ بانتظار تأكيد الكابتن': (
    'Customer confirmed payment; awaiting captain',
    'کڕیار پارەدانی پشتڕاست کردەوە؛ چاوەڕوانی کاپتن',
  ),
  'تم دفع واستلام أجور الخط': ('Route payment received', 'کرێی هێڵ وەرگیرا'),
  '⚠ تحذير: تأخر استلام الركاب': (
    '⚠ Delayed passenger pickup',
    '⚠ دواکەوتنی وەرگرتنی سەرنشین',
  ),
  '⚠ سُجّل تحذير تأخير لهذا المشوار': (
    '⚠ Delay warning recorded for this trip',
    '⚠ ئاگاداریی دواکەوتن بۆ ئەم گەشتە تۆمار کرا',
  ),
  'تلقي الطلبات': ('Receive requests', 'وەرگرتنی داواکارییەکان'),
  'جاهز تستقبل الطلبات؟': (
    'Ready to receive requests?',
    'ئامادەیت بۆ وەرگرتنی داواکاری؟',
  ),
  'ابدأ باستقبال الطلبات': (
    'Start receiving requests',
    'دەست بکە بە وەرگرتنی داواکارییەکان',
  ),
  'عندك طلب مشوار جديد': ('New trip request', 'داواکاریی گەشتێکی نوێ'),
  'اضغط لعرضه وقبوله قبل انتهاء العرض': (
    'Open and accept before it expires',
    'بیکەرەوە و پەسەندی بکە پێش بەسەرچوونی',
  ),
  'الأحد': ('Sunday', 'یەکشەممە'),
  'الاثنين': ('Monday', 'دووشەممە'),
  'الثلاثاء': ('Tuesday', 'سێشەممە'),
  'الأربعاء': ('Wednesday', 'چوارشەممە'),
  'الخميس': ('Thursday', 'پێنجشەممە'),
  'الجمعة': ('Friday', 'هەینی'),
  'السبت': ('Saturday', 'شەممە'),
};
String? lineCopy(String text, String lang) {
  String choose(String en, String ku) => lang == 'en' ? en : ku;
  final exact = lineTranslations[text];
  if (exact != null) return choose(exact.$1, exact.$2);
  final label = RegExp(r'^([^:\n]+): (.+)$', dotAll: true).firstMatch(text);
  if (label != null && lineTranslations.containsKey(label[1])) {
    final c = lineTranslations[label[1]]!;
    return '${choose(c.$1, c.$2)}: ${label[2]}';
  }
  var m = RegExp(r'^آخر يوم خدمة: (.+)$').firstMatch(text);
  if (m != null)
    return choose(
      'Last service day: ${m[1]}',
      'دوایین ڕۆژی خزمەتگوزاری: ${m[1]}',
    );
  m = RegExp(r'^الانطلاق (.+) • الوصول (.+)$').firstMatch(text);
  if (m != null)
    return choose(
      'Departure ${m[1]} • Arrival ${m[2]}',
      'دەستپێک ${m[1]} • گەیشتن ${m[2]}',
    );
  m = RegExp(r'^يبعد عن أقرب خط إلك ([0-9,]+) متر$').firstMatch(text);
  if (m != null)
    return choose(
      '${m[1]} m from your nearest route',
      '${m[1]} مەتر لە نزیکترین هێڵەکەت',
    );
  m = RegExp(r'^يبعد ([0-9,]+) متر عن هذا الخط$').firstMatch(text);
  if (m != null)
    return choose('${m[1]} m from this route', '${m[1]} مەتر لەم هێڵە');
  m = RegExp(
    r'^نقترح حتى ([0-9]+) خطوط ضمن 1 كم من أحد خطوطك\.$',
  ).firstMatch(text);
  if (m != null)
    return choose(
      'Up to ${m[1]} suggested routes within 1 km.',
      'تا ${m[1]} هێڵی پێشنیارکراو لە سنووری 1 کم.',
    );
  m = RegExp(r'^خطوطك ([0-9]+) من 3\n(.+)$', dotAll: true).firstMatch(text);
  if (m != null)
    return choose('Your routes: ${m[1]} of 3\n', 'هێڵەکانت: ${m[1]} لە 3\n') +
        (lineCopy(m[2]!, lang) ?? m[2]!);
  m = RegExp(r'^([0-9]+) يوم خدمة • (.+)$').firstMatch(text);
  if (m != null)
    return choose(
      '${m[1]} service days • ${m[2]}',
      '${m[1]} ڕۆژی خزمەتگوزاری • ${m[2]}',
    );
  m = RegExp(r'^(.+) لكل مدة الخط$').firstMatch(text);
  if (m != null)
    return choose(
      '${m[1]} for the full route term',
      '${m[1]} بۆ تەواوی ماوەی هێڵ',
    );
  m = RegExp(r'^أؤكد دفع (.+) للكابتن$').firstMatch(text);
  if (m != null)
    return choose('I paid ${m[1]} to the captain', '${m[1]}م دا بە کاپتن');
  return null;
}
