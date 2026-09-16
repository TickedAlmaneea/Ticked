import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/branch.dart';
import '../../models/cinema.dart';
import '../../models/film.dart';
import '../../models/film_break.dart';
import '../../models/schedule.dart';
import '../../services/live_activity_service.dart';
import '../../utils/date_format.dart';
import '../../widgets/segmented_timeline.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';

enum _Phase { editing, live, ended }

/// Proposal screens 7 & 8 — one screen, two (really three, counting
/// the summary) states, sharing a widget tree. Before Start it's an
/// editable preview and the manual-entry path; after Start the
/// editable fields disappear and the same timeline advances against
/// the clock; when the film ends, a summary replaces it.
class ScheduleCardScreen extends StatefulWidget {
  const ScheduleCardScreen({
    super.key,
    this.preselectedFilm,
    this.preselectedCinemaName,
    this.preselectedBranchId,
    this.initialTicketTime,
    this.fromTicketPhoto = false,
    this.titleOnTicket,
  });

  final Film? preselectedFilm;
  final String? preselectedCinemaName;
  final int? preselectedBranchId;
  final DateTime? initialTicketTime;

  /// Opened from a scanned ticket — shows a banner saying so, and naming
  /// whatever couldn't be read so the person knows what to fill in.
  final bool fromTicketPhoto;

  /// The film title as printed on a scanned ticket, for saying which
  /// film wasn't found in the cinema's listings.
  final String? titleOnTicket;

  @override
  State<ScheduleCardScreen> createState() => _ScheduleCardScreenState();
}

class _ScheduleCardScreenState extends State<ScheduleCardScreen> {
  _Phase _phase = _Phase.editing;

  List<Cinema> _cinemas = [];
  List<Film> _filmOptions = [];
  List<Branch> _branchOptions = [];

  /// True while a chosen cinema's branches and films are loading.
  bool _loadingOptions = false;

  /// False until the preselected cinema, branch and film have been
  /// checked — the ticket banner waits for it, so it doesn't briefly
  /// claim everything is missing.
  bool _preselectionChecked = false;

  Film? _film;
  String? _cinemaName;
  Branch? _branch;
  late DateTime _ticketTime;

  int? _adMinutes;
  List<FilmBreak> _breaks = [];
  bool _loadingBreaks = false;

  /// Set when the breaks lookup failed, so the card can say so in place
  /// with a retry — rather than implying the film has no safe breaks,
  /// which is a different thing entirely.
  bool _breaksFailed = false;

  DateTime? _liveStartedAt;
  Timer? _ticker;
  bool _demoSpeedEnabled = false;
  static const _demoSpeedMultiplier = 90;

  @override
  void initState() {
    super.initState();
    _film = widget.preselectedFilm;
    _cinemaName = widget.preselectedCinemaName;
    _ticketTime = widget.initialTicketTime ?? DateTime.now();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    LiveActivityService.instance.end();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cinemas = await appRepository.cinemas();
    if (!mounted) return;
    setState(() => _cinemas = cinemas);

    // The same title is listed separately by every chain (and can be more
    // than once), so a film only means something within its cinema. A
    // preselected cinema that isn't a real one — an OCR guess, say — is
    // dropped along with the film, and the person starts from the cinema.
    final cinemaName = _cinemaName;
    if (cinemaName != null && cinemas.any((c) => c.name == cinemaName)) {
      await _onCinemaChanged(cinemaName, keepFilm: true, keepBranchId: widget.preselectedBranchId);
    } else {
      setState(() {
        _cinemaName = null;
        _film = null;
      });
    }
    if (mounted) setState(() => _preselectionChecked = true);
  }

  /// Order is forced: cinema, then branch, then a film from that cinema's
  /// own listings. Choosing a cinema clears everything below it.
  ///
  /// [keepFilm] keeps a preselected film when it really is one of this
  /// cinema's listings (opened from the Cinemas tab or a ticket photo).
  /// [keepBranchId] does the same for a branch read off a ticket.
  Future<void> _onCinemaChanged(String? name, {bool keepFilm = false, int? keepBranchId}) async {
    if (name == null) return;
    final previousFilm = _film;
    setState(() {
      _cinemaName = name;
      _branch = null;
      _branchOptions = [];
      _filmOptions = [];
      _film = null;
      _adMinutes = null;
      _breaks = [];
      _breaksFailed = false;
      _loadingOptions = true;
    });

    final (branches, films) = await (appRepository.branches(name), appRepository.filmsForCinema(name)).wait;
    // Ignore a slow answer for a cinema the person has already moved off.
    if (!mounted || _cinemaName != name) return;

    final keptFilm = keepFilm && previousFilm != null && films.contains(previousFilm) ? previousFilm : null;
    // The dropdown needs the very instance from its own items, so look
    // the branch up in this list rather than keep one passed in.
    final keptBranch = branches.where((b) => b.id == keepBranchId).firstOrNull;
    setState(() {
      _branchOptions = branches;
      _filmOptions = films;
      _branch = keptBranch;
      _film = keptFilm;
      _loadingOptions = false;
    });
    if (keptFilm != null) await _loadBreaksAndAdMinutes();
  }

  Future<void> _onFilmChanged(Film? film) async {
    if (film == null) return;
    setState(() {
      _film = film;
      _breaks = [];
    });
    await _loadBreaksAndAdMinutes();
  }

  Future<void> _loadBreaksAndAdMinutes() async {
    await _loadAdMinutes();
    await _loadBreaks();
  }

  /// Depends on the chain and the film's length — cheap, a cached
  /// `cinemas` lookup.
  Future<void> _loadAdMinutes() async {
    final film = _film;
    final cinemaName = _cinemaName;
    if (film != null && cinemaName != null) {
      final ad = await appRepository.adMinutes(cinemaName, film.durationMin);
      if (mounted) setState(() => _adMinutes = ad);
    }
  }

  /// Depends on the film ONLY — never the cinema or branch. Kept apart
  /// from [_loadAdMinutes] so changing chain doesn't re-run it: on a film
  /// whose breaks aren't cached yet, every rerun can reach Gemini, and
  /// flipping between chains would spend daily quota for nothing.
  Future<void> _loadBreaks() async {
    final film = _film;
    if (film != null) {
      setState(() {
        _loadingBreaks = true;
        _breaksFailed = false;
      });
      try {
        final breaks = await appRepository.breaksForFilm(film.filmId);

        // Re-read the film after the breaks lookup. The lookup can be
        // what writes `credits_start_min` (on a first ask), and the Film
        // this screen was opened with was loaded before that — from the
        // Cinemas tab, possibly long before. Without this, the credits
        // are correct in the database and missing from the timeline.
        // A plain row read; it never calls Gemini.
        final fresh = await appRepository.filmDetails(film.filmId);

        if (!mounted) return;
        setState(() {
          _breaks = breaks;
          // Only if the person hasn't picked a different film meanwhile.
          if (_film?.filmId == fresh.filmId) _film = fresh;
        });
      } catch (e) {
        // GeminiApi has already retried and tried its fallback model, so
        // reaching here means Gemini is genuinely unavailable for now.
        // The schedule is still correct without safe windows — the ad
        // block is what this screen is for — so the card says so quietly
        // with a retry, instead of an alarming snackbar. Nothing was
        // cached, so reopening the film later asks again by itself.
        debugPrint('Safe breaks unavailable: $e');
        if (!mounted) return;
        setState(() {
          _breaks = [];
          _breaksFailed = true;
        });
      } finally {
        if (mounted) setState(() => _loadingBreaks = false);
      }
    }
  }

  /// Opens the cinema's own page for this film in the phone's browser,
  /// where their booking flow lives. Deliberately external rather than
  /// an in-app webview: buying involves payment and a login on the
  /// cinema's own domain, which a person should see in a real browser
  /// with a real address bar.
  Future<void> _openBookingPage() async {
    final url = _film?.bookingUrl;
    if (url == null) return;

    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Couldn\'t open $url')),
    );
  }

  Future<void> _pickTicketTime() async {
    // Widened to include the current ticket time: a scanned ticket can
    // be older than yesterday, and showDatePicker throws when its
    // initial date falls outside the range.
    final earliest = DateTime.now().subtract(const Duration(days: 1));
    final latest = DateTime.now().add(const Duration(days: 60));
    final date = await showDatePicker(
      context: context,
      initialDate: _ticketTime,
      firstDate: _ticketTime.isBefore(earliest) ? _ticketTime : earliest,
      lastDate: _ticketTime.isAfter(latest) ? _ticketTime : latest,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_ticketTime));
    if (time == null) return;
    setState(() {
      _ticketTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Schedule? get _schedule {
    final film = _film;
    final branch = _branch;
    final ad = _adMinutes;
    if (film == null || branch == null || ad == null) return null;
    // A film the cinema hasn't published a runtime for yet. Every
    // minute on the timeline is measured from it, so there is no
    // schedule to build — [_buildIncompleteHint] says which it is.
    if (!film.hasKnownDuration) return null;
    return Schedule(branch: branch, film: film, ticketTime: _ticketTime, adMinutes: ad, breaks: _breaks);
  }

  Duration get _elapsedRealDuration =>
      _liveStartedAt == null ? Duration.zero : DateTime.now().difference(_liveStartedAt!);

  int get _elapsedSeconds {
    final real = _elapsedRealDuration.inSeconds;
    return _demoSpeedEnabled ? real * _demoSpeedMultiplier : real;
  }

  int get _elapsedMinutes => _elapsedSeconds ~/ 60;

  Future<void> _start() async {
    final schedule = _schedule;
    if (schedule == null) return;
    await appRepository.recordAttendance(schedule);
    setState(() {
      _liveStartedAt = DateTime.now();
      _phase = _Phase.live;
    });
    unawaited(LiveActivityService.instance.start(schedule));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      unawaited(LiveActivityService.instance.onTick(schedule, _elapsedMinutes));
      if (_elapsedMinutes >= schedule.totalMinutes) _endSession();
    });
  }

  void _endSession() {
    _ticker?.cancel();
    unawaited(LiveActivityService.instance.end());
    if (mounted) setState(() => _phase = _Phase.ended);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (_phase == _Phase.live) {
                          _confirmLeaveLiveSession();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text(
                      _phase == _Phase.editing ? 'Schedule' : 'Live Session',
                      style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: switch (_phase) {
                    _Phase.editing => _buildEditing(schedule),
                    _Phase.live => _buildLive(schedule!),
                    _Phase.ended => _buildEnded(schedule!),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeaveLiveSession() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Leave Live Session?', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: Text('The countdown keeps running while the app is open. Leaving now ends it.', style: AppTypography.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _ticker?.cancel();
      unawaited(LiveActivityService.instance.end());
      Navigator.of(context).pop();
    }
  }

  // ---- Editing / preview (screen 7) ---------------------------------------

  Widget _buildEditing(Schedule? schedule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fromTicketPhoto && _preselectionChecked) ...[
          _OcrHintBanner(message: _ticketBannerMessage()),
          const SizedBox(height: 18),
        ],
        Text('CINEMA', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildCinemaDropdown(),
        const SizedBox(height: 20),
        Text('BRANCH', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildBranchDropdown(),
        const SizedBox(height: 20),
        Text('FILM', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildFilmDropdown(),
        const SizedBox(height: 20),
        Text('TICKET TIME', style: AppTypography.overline),
        const SizedBox(height: 8),
        _buildTicketTimeField(),
        const SizedBox(height: 28),
        if (schedule != null) _buildScheduleSummary(schedule) else _buildIncompleteHint(),
        const SizedBox(height: 28),
        TickedPrimaryButton(label: 'Start', onPressed: schedule == null ? null : _start),
        if (_film?.bookingUrl != null) ...[
          const SizedBox(height: 24),
          _BuyTicketLink(onOpen: _openBookingPage),
        ],
      ],
    );
  }

  /// Names what the ticket scan left empty, from the card's current
  /// state — so once the person fills a field in, it drops out.
  String _ticketBannerMessage() {
    final missing = [
      if (_cinemaName == null) 'cinema',
      if (_branch == null) 'branch',
      if (_film == null) 'film',
      if (widget.initialTicketTime == null) 'ticket time',
    ];
    if (missing.isEmpty) {
      return 'Filled in from your ticket photo — double-check before starting.';
    }

    final list = missing.length == 1
        ? missing.first
        : '${missing.sublist(0, missing.length - 1).join(', ')} and ${missing.last}';
    final notListed = _film == null && _cinemaName != null && widget.titleOnTicket != null
        ? ' "${widget.titleOnTicket}" isn\'t in $_cinemaName\'s listings.'
        : '';
    return 'Filled in from your ticket photo, but the $list couldn\'t be read — '
        'please fill ${missing.length == 1 ? 'it' : 'them'} in below.$notListed';
  }

  Widget _buildCinemaDropdown() {
    return _DropdownShell<String>(
      value: _cinemaName,
      hint: 'Choose a cinema',
      items: _cinemas.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
      onChanged: (name) => _onCinemaChanged(name),
    );
  }

  Widget _buildBranchDropdown() {
    final String hint;
    if (_cinemaName == null) {
      hint = 'Choose a cinema first';
    } else if (_loadingOptions) {
      hint = 'Loading branches…';
    } else if (_branchOptions.isEmpty) {
      hint = 'No branches listed for $_cinemaName';
    } else {
      hint = 'Choose a branch';
    }

    return _DropdownShell<Branch>(
      value: _branch,
      hint: hint,
      items: _branchOptions.map((b) => DropdownMenuItem(value: b, child: Text(b.branchName))).toList(),
      onChanged: _branchOptions.isEmpty ? null : (b) => setState(() => _branch = b),
    );
  }

  /// Only the chosen cinema's own listings, and only once a branch is
  /// picked — so the right one of several same-titled films is chosen.
  Widget _buildFilmDropdown() {
    final String hint;
    if (_cinemaName == null) {
      hint = 'Choose a cinema first';
    } else if (_loadingOptions) {
      hint = 'Loading films…';
    } else if (_filmOptions.isEmpty) {
      hint = 'No films listed for $_cinemaName yet';
    } else if (_branch == null) {
      hint = 'Choose a branch first';
    } else {
      hint = 'Choose a film';
    }

    return _DropdownShell<Film>(
      value: _film,
      hint: hint,
      items: _filmOptions.map((f) => DropdownMenuItem(value: f, child: Text(f.title))).toList(),
      onChanged: _branch == null || _filmOptions.isEmpty ? null : _onFilmChanged,
    );
  }

  Widget _buildTicketTimeField() {
    return GestureDetector(
      onTap: _pickTicketTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 10),
            Text(formatDateAndClock(_ticketTime), style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('Change', style: AppTypography.label.copyWith(color: AppColors.gold)),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompleteHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Text(
        _film != null && !_film!.hasKnownDuration
            ? '${_film!.title} has no running time listed yet, so its schedule '
                  'can\'t be worked out. Pick another film, or try again once '
                  'the cinema publishes one.'
            : 'Pick a cinema, branch and film to see the real start and end time.',
        style: AppTypography.bodyMedium,
      ),
    );
  }

  Widget _buildScheduleSummary(Schedule schedule) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Starts ${formatClock(schedule.trueStartTime)} · ends ${formatClock(schedule.trueEndTime)}',
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('${schedule.adMinutes} min of advertising, researched at ${schedule.branch.cinemaName}', style: AppTypography.bodySmall),
          const SizedBox(height: 16),
          SegmentedTimeline(segments: schedule.buildTimeline(), totalMinutes: schedule.totalMinutes),
          const SizedBox(height: 10),
          _buildLegend(),
          if (_loadingBreaks) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                ),
                const SizedBox(width: 8),
                Text('Finding safe breaks…', style: AppTypography.bodySmall),
              ],
            ),
          ] else if (_breaksFailed) ...[
            // Checked before "no breaks found": a failed lookup and a
            // film with no safe windows look identical in the data (an
            // empty list), but they tell a person very different things.
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Safe breaks aren\'t available right now. The schedule above is still correct.',
                    style: AppTypography.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _loadBreaks,
                  child: Text('Try again', style: AppTypography.label.copyWith(color: AppColors.gold)),
                ),
              ],
            ),
          ] else if (schedule.breaks.isEmpty) ...[
            const SizedBox(height: 10),
            Text('No safe breaks found for this film.', style: AppTypography.bodySmall),
          ] else if (schedule.breaks.first.isEstimated) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Estimated from this film\'s runtime and pacing — nobody has '
                    'confirmed these scenes yet.',
                    style: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.bodySmall),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        dot(AppColors.timelineAds, 'Ads'),
        dot(AppColors.timelineFilm, 'Film'),
        dot(AppColors.timelineBreak, 'Safe break'),
        dot(AppColors.timelineCredits, 'Credits'),
      ],
    );
  }

  // ---- Live (screen 8) ----------------------------------------------------

  Widget _buildLive(Schedule schedule) {
    final remainingSeconds = (schedule.totalMinutes * 60) - _elapsedSeconds;
    final nextBreak = schedule.nextBreakAfter(_elapsedMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(schedule.film.title, style: AppTypography.displayMedium, textAlign: TextAlign.center),
        Text('${schedule.branch.cinemaName} · ${schedule.branch.branchName}', style: AppTypography.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              Text('TIME REMAINING', style: AppTypography.overline),
              const SizedBox(height: 4),
              Text(formatCountdown(Duration(seconds: remainingSeconds < 0 ? 0 : remainingSeconds)), style: AppTypography.timerLarge),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SegmentedTimeline(
          segments: schedule.buildTimeline(),
          totalMinutes: schedule.totalMinutes,
          elapsedMin: _elapsedMinutes,
        ),
        const SizedBox(height: 10),
        _buildLegend(),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: nextBreak == null
              ? Text('No more safe breaks in this screening.', style: AppTypography.bodyMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT SAFE BREAK', style: AppTypography.overline),
                    const SizedBox(height: 4),
                    Text(
                      _elapsedMinutes >= schedule.adMinutes + nextBreak.startMin
                          ? 'Now, for ${nextBreak.lengthMin} more min'
                          : 'In ${schedule.adMinutes + nextBreak.startMin - _elapsedMinutes} min, for ${nextBreak.lengthMin} min',
                      style: AppTypography.bodyLarge.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        SwitchListTile(
          value: _demoSpeedEnabled,
          onChanged: (v) => setState(() => _demoSpeedEnabled = v),
          activeColor: AppColors.gold,
          contentPadding: EdgeInsets.zero,
          title: Text('Demo speed', style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
          subtitle: Text('Compresses the screening for a live demo — judging only.', style: AppTypography.bodySmall),
        ),
        const SizedBox(height: 8),
        TickedSecondaryButton(label: 'End session', onPressed: _endSession),
      ],
    );
  }

  // ---- Ended / summary -----------------------------------------------------

  Widget _buildEnded(Schedule schedule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.check_circle_outline, color: AppColors.gold, size: 44),
        const SizedBox(height: 14),
        Text('Session complete', style: AppTypography.displayMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(schedule.film.title, style: AppTypography.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(value: '${schedule.adMinutes}', label: 'MIN OF ADS ENDURED'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(value: '${schedule.breaks.length}', label: 'SAFE BREAKS TAKEN'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        TickedPrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// "Buy a ticket for this film" — a link out to the cinema's own page
/// for it, built from the slug the scraper stored. Ticked never sells a
/// ticket itself; it works out when the film really starts once you
/// have one.
class _BuyTicketLink extends StatelessWidget {
  const _BuyTicketLink({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              'Don\'t have a ticket?',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Then buy one from here!',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.gold,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.gold,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new, size: 14, color: AppColors.gold),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrHintBanner extends StatelessWidget {
  const _OcrHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(value, style: AppTypography.displayLarge.copyWith(color: AppColors.gold)),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.overline, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _DropdownShell<T> extends StatelessWidget {
  const _DropdownShell({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    // ignore: unused_element_parameter
    super.key,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;

  /// Null locks the dropdown (e.g. branch before a cinema is chosen).
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hintText = Text(hint, style: AppTypography.bodyLarge.copyWith(color: AppColors.textDisabled));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: hintText,
          disabledHint: hintText,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textTertiary),
          iconDisabledColor: AppColors.textDisabled,
          dropdownColor: AppColors.surface2,
          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
