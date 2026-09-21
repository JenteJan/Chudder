/// How long a horizontal row is: how many items it asks the server for.
///
/// A row builds its items lazily - every one of them is a `ListView.separated`
/// with an `itemBuilder` - so a long row costs a longer answer to read and
/// nothing else until somebody scrolls it. The cap is what stops a library of
/// thousands arriving as one row.
const kRowItemLimit = 60;

/// The same, for the rows that come one per category.
///
/// Genres are a row each and a library can hold forty of them; the movie
/// recommendations are six; "recently added" is one row per library on the
/// dashboard. Kept as its own cap so those can be made shorter than the single
/// rows if the combined answer grows too slow to read.
const kCategoryRowItemLimit = 60;
