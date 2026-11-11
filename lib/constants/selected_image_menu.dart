enum SelectedImageMenu {
  // copyTo(text: 'COPY TO'),
  moveTo(text: 'MOVE TO'),
  lock(text: 'LOCK (HIDE)');

  const SelectedImageMenu({required this.text});
  final String text;
}
