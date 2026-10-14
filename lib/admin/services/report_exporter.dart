import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/attendance_rules.dart';
import '../../core/utils/dates.dart';
import 'report_builder.dart';

enum ExportFormat { excel, csv, pdf }

/// Turns report rows into downloadable Excel / CSV / PDF files.
class ReportExporter {
  ReportExporter._();

  static final _hm = DateFormat('HH:mm');

  static const detailHeader = [
    'Date',
    'Employee',
    'Code',
    'Status',
    'Check in',
    'Check out',
    'Worked (h)',
    'Late (min)',
    'Site',
    'Flagged',
  ];

  static const summaryHeader = [
    'Employee',
    'Code',
    'Present',
    'Late',
    'Half day',
    'Absent',
    'Weekly off',
    'Worked (h)',
    'Late (min)',
    'Flagged',
  ];

  static List<Object> detailRow(ReportRow r) => [
    dateKey(r.day),
    r.employee.name,
    r.employee.employeeCode,
    r.eval.status.label,
    r.record == null ? '' : _hm.format(r.record!.checkIn.time),
    r.record?.checkOut == null ? '' : _hm.format(r.record!.checkOut!.time),
    (r.eval.workedMinutes / 60).toStringAsFixed(2),
    r.eval.lateMinutes,
    r.record?.checkIn.siteName ?? '',
    (r.record?.flagged ?? false) ? 'Yes' : '',
  ];

  static List<Object> summaryRow(EmployeeSummary s) => [
    s.employee.name,
    s.employee.employeeCode,
    s.present,
    s.late,
    s.halfDay,
    s.absent,
    s.weeklyOff,
    (s.workedMinutes / 60).toStringAsFixed(2),
    s.lateMinutes,
    s.flagged,
  ];

  static Uint8List csv(List<ReportRow> rows) {
    final data = [
      detailHeader,
      for (final r in rows) detailRow(r),
    ];
    // BOM so Excel opens UTF-8 names correctly.
    return Uint8List.fromList(utf8.encode('﻿${Csv().encode(data)}'));
  }

  static Uint8List excel(List<ReportRow> rows, List<EmployeeSummary> summary) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();

    CellValue cell(Object v) => switch (v) {
      int i => IntCellValue(i),
      double d => DoubleCellValue(d),
      _ => TextCellValue('$v'),
    };

    final summarySheet = book['Summary'];
    summarySheet.appendRow([for (final h in summaryHeader) TextCellValue(h)]);
    for (final s in summary) {
      summarySheet.appendRow([for (final v in summaryRow(s)) cell(v)]);
    }

    final detail = book['Daily'];
    detail.appendRow([for (final h in detailHeader) TextCellValue(h)]);
    for (final r in rows) {
      detail.appendRow([for (final v in detailRow(r)) cell(v)]);
    }

    if (defaultSheet != null && defaultSheet != 'Summary') {
      book.delete(defaultSheet);
    }
    book.setDefaultSheet('Summary');
    return Uint8List.fromList(book.encode()!);
  }

  static Future<Uint8List> pdf(
    List<ReportRow> rows,
    List<EmployeeSummary> summary, {
    required String title,
  }) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Text(
          title,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text('Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: summaryHeader,
            data: [for (final s in summary) summaryRow(s)],
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Daily detail', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: detailHeader,
            data: [for (final r in rows) detailRow(r)],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> download(
    ExportFormat format,
    List<ReportRow> rows,
    List<EmployeeSummary> summary, {
    required String baseName,
    required String title,
  }) async {
    switch (format) {
      case ExportFormat.excel:
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: excel(rows, summary),
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      case ExportFormat.csv:
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: csv(rows),
          fileExtension: 'csv',
          mimeType: MimeType.csv,
        );
      case ExportFormat.pdf:
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: await pdf(rows, summary, title: title),
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
    }
  }
}
