WITH relevant_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 51 AND 61
),
ecg_procedures_count AS (
  SELECT pe.subject_id, COUNT(DISTINCT pe.itemid) AS num_ecg_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%telemetry%')
  AND pe.subject_id IN (SELECT subject_id FROM relevant_patients)
  GROUP BY pe.subject_id
)
SELECT APPROX_QUANTILES(num_ecg_procedures, 100)[OFFSET(25)] AS percentile_25
FROM ecg_procedures_count;