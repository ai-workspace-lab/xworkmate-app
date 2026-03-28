part of 'assistant_page.dart';

const double _skillPickerPreferredMaxHeight = 460;
const double _skillPickerMinHeight = 220;
const double _skillPickerVerticalGap = 8;

Widget _buildSkillPickerOverlayFor(
  _ComposerBarState state,
  BuildContext context,
) {
  final mediaQuery = MediaQuery.of(context);
  final targetBox =
      state._skillPickerTargetKey.currentContext?.findRenderObject()
          as RenderBox?;
  final targetOrigin = targetBox?.localToGlobal(Offset.zero);
  final targetSize = targetBox?.size;
  final availableBelow = targetOrigin == null || targetSize == null
      ? _skillPickerPreferredMaxHeight
      : mediaQuery.size.height -
            mediaQuery.padding.bottom -
            (targetOrigin.dy + targetSize.height) -
            _skillPickerVerticalGap;
  final availableAbove = targetOrigin == null
      ? _skillPickerPreferredMaxHeight
      : targetOrigin.dy - mediaQuery.padding.top - _skillPickerVerticalGap;
  final openUpward =
      availableBelow < _skillPickerMinHeight && availableAbove > availableBelow;
  final constrainedHeight = math.max(
    _skillPickerMinHeight,
    openUpward ? availableAbove : availableBelow,
  );
  final maxHeight = math.min(_skillPickerPreferredMaxHeight, constrainedHeight);
  return Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: state._hideSkillPicker,
          child: const SizedBox.expand(),
        ),
      ),
      CompositedTransformFollower(
        link: state._skillPickerLayerLink,
        showWhenUnlinked: false,
        targetAnchor: openUpward ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: openUpward ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, openUpward ? -_skillPickerVerticalGap : 8),
        child: _SkillPickerPopover(
          maxHeight: maxHeight,
          searchController: state._skillPickerSearchController,
          searchFocusNode: state._skillPickerSearchFocusNode,
          selectedSkillKeys: state.widget.selectedSkillKeys,
          filteredSkills: state._filteredSkillOptions(),
          isLoading: state._refreshingSingleAgentSkills,
          hasQuery: state._skillPickerQuery.trim().isNotEmpty,
          onQueryChanged: state._setSkillPickerQuery,
          onToggleSkill: (skillKey) => state.widget.onToggleSkill(skillKey),
        ),
      ),
    ],
  );
}
