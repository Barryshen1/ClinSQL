WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 81 AND 91
),
ecg_telemetry_procedures AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ecg%' OR LOWER(label) LIKE '%telemetry%' OR LOWER(label) LIKE '%ekg%'
),
procedure_counts AS (
  SELECT pe.subject_id, COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN ecg_telemetry_procedures et ON pe.itemid = et.itemid
  JOIN patient_filter pf ON pe.subject_id = pf.subject_id
  GROUP BY pe.subject_id
)
SELECT STDDEV(distinct_procedure_count) AS sd_distinct_ecg_telemetry_procedures
FROM procedure_counts;