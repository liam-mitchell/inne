#include <ScreenCapture.au3>

Func Screenshots($prefix, $rows, $columns)
   $window = WinGetHandle("NPP")
   $left = 3
   $top = WinGetPos("NPP")[3] - WinGetClientSize("NPP")[1] + 3
   $right = WinGetClientSize("NPP")[0] - 3
   $bottom = WinGetClientSize("NPP")[1] - 3

   For $row = 0 To $rows - 1
	  $rowname = "A"
	  If $row == 1 Then
		 $rowname = "B"
	  ElseIf $row == 2 Then
		 $rowname = "C"
	  ElseIf $row == 3 Then
		 $rowname = "D"
	  ElseIf $row == 4 Then
 		 $rowname = "E"
	  ElseIf $row == 5 Then
		 $rowname = "X"
	  EndIf

	  For $col = 0 To $columns - 1
 		 $colname = "00"
		 If $col < 10 Then
			$colname = "0" & $col
		 Else
			$colname = "" & $col
		 EndIf

		 Send("{SPACE}")
		 Sleep(500)

		 For $level = 0 To 4
			$levelname = "0" & $level
			$filename = "C:\Users\Liam\workspace\inne++\screenshots\" & $prefix & "-" & $rowname & "-" & $colname & "-" & $levelname & ".jpg"

			Send("{ENTER}")
			Sleep(500)
			Send("{SPACE}")
			Sleep(1)
			_ScreenCapture_CaptureWnd($filename, $window, $left, $top, $right, $bottom, False)
			Send("{ESCAPE}")
 			Sleep(1)
			Send("{DOWN}")
			Sleep(1)
			Send("{DOWN}")
			Sleep(1)
			Send("{ENTER}")
			Sleep(50)
			Send("{RIGHT}")
			Sleep(50)
		 Next

		 Send("{ESCAPE}")
		 Sleep(500)

		 If $col < $columns - 1 Then
			Send("{RIGHT}")
		 EndIf
	  Next

	  Send("{DOWN}")

	  For $col = 0 To $columns - 2
		 Sleep(50)
		 Send("{LEFT}")
	  Next
   Next
EndFunc

Func EpisodeScreenshots($prefix, $rows, $columns)
   $window = WinGetHandle("NPP")
   $left = 3
   $top = 553
   $right = 1078
   $bottom = 783

   For $row = 0 To $rows - 1
	  $rowname = "A"
	  If $row == 1 Then
		 $rowname = "B"
	  ElseIf $row == 2 Then
		 $rowname = "C"
	  ElseIf $row == 3 Then
		 $rowname = "D"
	  ElseIf $row == 4 Then
 		 $rowname = "E"
	  ElseIf $row == 5 Then
		 $rowname = "X"
	  EndIf

	  For $col = 0 To $columns - 1
 		 $colname = "00"
		 If $col < 10 Then
			$colname = "0" & $col
		 Else
			$colname = "" & $col
		 EndIf

		 Sleep(500)

		 $filename = "C:\Users\Liam\workspace\inne++\screenshots\" & $prefix & "-" & $rowname & "-" & $colname & ".jpg"
		 _ScreenCapture_CaptureWnd($filename, $window, $left, $top, $right, $bottom, False)

		 ;Send("{ESCAPE}")

		 If $col < $columns - 1 Then
			Send("{RIGHT}")
		 EndIf
	  Next

	  Send("{DOWN}")

	  For $col = 0 To $columns - 2
		 Sleep(50)
		 Send("{LEFT}")
	  Next
   Next
EndFunc

Func LevelNameScreenshots($prefix, $rows, $columns)
   $window = WinGetHandle("NPP")
   $left = 50
   $top = 750
   $right = 1000
   $bottom = 850

   Send("{SPACE}");
   Sleep(1000);

   For $col = 0 To $columns - 1
	  $colname = "00"
	  If $col < 10 Then
		$colname = "0" & $col
	  Else
		$colname = "" & $col
	  EndIf

	  For $row = 0 To 4
		 $rowname = "A"
		 If $row == 1 Then
			$rowname = "B"
		 ElseIf $row == 2 Then
			$rowname = "C"
		 ElseIf $row == 3 Then
			$rowname = "D"
		 ElseIf $row == 4 Then
			$rowname = "E"
		 EndIf

		 For $level = 0 to 4
			$levelname = "0" & $level
			$filename = "C:\Users\Liam\workspace\inne++\screenshots\names\" & $prefix & "-" & $rowname & "-" & $colname & "-" & $levelname & ".jpg"
			_ScreenCapture_CaptureWnd($filename, $window, $left, $top, $right, $bottom, False)

			If $level < 4 Then
			   Send("{RIGHT}");
			   Sleep(500);
			EndIf
		 Next

		 Send("{DOWN}");

		 For $i = 0 to 4
			Sleep(50);
			Send("{LEFT}");
		 Next

		 Sleep(500);
	  Next
   Next

   If $rows == 6 Then
	  For $col = 0 To $columns - 1
		 $rowname = "X"
		 $colname = "00"
		 If $col < 10 Then
			$colname = "0" & $col
		 Else
			$colname = "" & $col
		 EndIf

		 For $level = 0 to 4
			$levelname = "0" & $level
			$filename = "C:\Users\Liam\workspace\inne++\screenshots\names\" & $prefix & "-" & $rowname & "-" & $colname & ".jpg"
			_ScreenCapture_CaptureWnd($filename, $window, $left, $top, $right, $bottom, False)

			If $level < 4 Then
			   Send("{RIGHT}");
			   Sleep(500);
			EndIf
		 Next

		 Send("{DOWN}");

		 For $i = 0 to 4
			Sleep(50);
			Send("{LEFT}");
		 Next

		 Sleep(500);
	  Next
   EndIf

   Send("{ESCAPE}");
EndFunc

WinWaitActive("NPP")
Send("{ENTER}")
Sleep(1)
Send("{ENTER}")
Sleep(1)

;Send("{PGUP}")
;;Sleep(500)
;;LevelNameScreenshots("SI", 5, 5)
;Sleep(500)
;Send("{PGDN}")

Sleep(500)
LevelNameScreenshots("S", 6, 20)

Sleep(500)
Send("{PGDN}")
Sleep(500)
LevelNameScreenshots("SL", 6, 20)
