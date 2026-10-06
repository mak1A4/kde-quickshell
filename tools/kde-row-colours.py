# Prints the palette a KDE application really gets in this session (from the
# platform theme) and the colours Breeze paints a list row in with it, in each
# state: hover, selected, both, in an active and an inactive window. For
# checking a colour scheme the shell wrote. No window is shown.
#
#   QT_QPA_PLATFORMTHEME=kde python3 tools/kde-row-colours.py
import sys
from PyQt6.QtWidgets import QApplication, QStyleOptionViewItem, QStyle, QListView
from PyQt6.QtGui import QImage, QPainter, QPalette, QColor
from PyQt6.QtCore import QRect
app = QApplication(sys.argv)
print('style:', app.style().objectName(), '| platform:', app.platformName())
pal = app.palette()
G, R = QPalette.ColorGroup, QPalette.ColorRole
for g in (G.Active, G.Inactive):
    print(f'{g.name:9s}', ' '.join(f'{r.name}={pal.color(g, r).name()}' for r in (R.Window, R.Base, R.AlternateBase, R.Highlight, R.HighlightedText, R.Text, R.Button)))
view = QListView()
S = QStyle.StateFlag
def row(name, state, behind):
    img = QImage(200, 40, QImage.Format.Format_ARGB32); img.fill(behind)
    p = QPainter(img)
    opt = QStyleOptionViewItem(); opt.initFrom(view); opt.rect = QRect(0, 0, 200, 40); opt.state = state
    opt.viewItemPosition = QStyleOptionViewItem.ViewItemPosition.OnlyOne; opt.showDecorationSelected = True
    app.style().drawPrimitive(QStyle.PrimitiveElement.PE_PanelItemViewItem, opt, p, view); p.end()
    print(f'  {name:28s} middle {img.pixelColor(100, 20).name()}  edge {img.pixelColor(100, 1).name()}')
win = pal.color(G.Active, R.Window)
print('on the window colour', win.name())
row('hover', S.State_Enabled | S.State_Active | S.State_MouseOver, win)
row('hover, window not active', S.State_Enabled | S.State_MouseOver, win)
row('selected', S.State_Enabled | S.State_Active | S.State_Selected, win)
row('selected, window not active', S.State_Enabled | S.State_Selected, win)
row('selected + hover', S.State_Enabled | S.State_Active | S.State_Selected | S.State_MouseOver, win)
row('selected + hover, not active', S.State_Enabled | S.State_Selected | S.State_MouseOver, win)
