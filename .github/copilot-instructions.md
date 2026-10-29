# Project context
Flutter app (package: product_inventory) for a bakery marketplace. Customers
browse stores/products; sellers run a store and post products.

Stack: Firebase Auth + Firebase Realtime Database (NOT Firestore), Provider
(StreamProvider for auth), singleton ChangeNotifier stores (CartStore,
FavoritesStore) in lib/service/ or lib/screen/home/. Images go to Cloudinary
via lib/service/storage_service.dart (don't touch it). No Cloud Functions yet
(no Blaze plan), so all logic is client-side plus database rules.

Structure: lib/model, lib/service (database.dart is the single data-access
class), lib/screen/{authenticate,home,seller}, lib/shared (app_theme.dart has
kShopName, formatPeso, AppColors). Roles: users/{uid}/role = customer|seller.
Stores live at stores/{sellerUid}; products at products/{id} with sellerId.

Standards: explicit types, null safety, loading/error/empty states in every
screen, create streams once (initState or late final field), never inside
build(). Wrap awaits with try/catch and show a SnackBar on failure. Check
`mounted` after awaits. Use debugPrint, not print. Keep the existing UI
style (cream background, brown app bar, pink accent). Do not reformat
unrelated code. Never edit lib/service/storage_service.dart.

Database rules are in database.rules.json at the project root. Whenever you
change the data model, update that file too, and list the change so I can
publish it in the Firebase console. I publish rules manually.