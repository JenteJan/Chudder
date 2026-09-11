/// What the rating sites say about something, gathered from wherever it can
/// be had: Jellyseerr proxies Rotten Tomatoes and IMDb, TMDB's own average
/// comes with its details, and OMDb - with a key of the user's own - adds
/// IMDb, Rotten Tomatoes and Metacritic without any of that.
class ExternalRatings {
  /// Out of ten.
  final double? imdb;
  final int? imdbVotes;

  /// Out of ten.
  final double? tmdb;
  final int? tmdbVotes;

  /// Percentages.
  final int? rtCritics;
  final int? rtAudience;

  /// Out of a hundred.
  final int? metacritic;

  final String? imdbUrl;
  final String? rtUrl;
  final String? metacriticUrl;

  const ExternalRatings({
    this.imdb,
    this.imdbVotes,
    this.tmdb,
    this.tmdbVotes,
    this.rtCritics,
    this.rtAudience,
    this.metacritic,
    this.imdbUrl,
    this.rtUrl,
    this.metacriticUrl,
  });

  static const empty = ExternalRatings();

  bool get isEmpty => imdb == null && tmdb == null && rtCritics == null && rtAudience == null && metacritic == null;

  /// This, with whatever [other] knows that this does not.
  ExternalRatings merge(ExternalRatings? other) {
    if (other == null) return this;
    return ExternalRatings(
      imdb: imdb ?? other.imdb,
      imdbVotes: imdbVotes ?? other.imdbVotes,
      tmdb: tmdb ?? other.tmdb,
      tmdbVotes: tmdbVotes ?? other.tmdbVotes,
      rtCritics: rtCritics ?? other.rtCritics,
      rtAudience: rtAudience ?? other.rtAudience,
      metacritic: metacritic ?? other.metacritic,
      imdbUrl: imdbUrl ?? other.imdbUrl,
      rtUrl: rtUrl ?? other.rtUrl,
      metacriticUrl: metacriticUrl ?? other.metacriticUrl,
    );
  }
}

/// What the lookup is keyed on. A record, so two pages asking about the same
/// film share one answer.
typedef ExternalRatingsRequest = ({int? tmdbId, String? imdbId, bool isSeries, String title, int? year});
