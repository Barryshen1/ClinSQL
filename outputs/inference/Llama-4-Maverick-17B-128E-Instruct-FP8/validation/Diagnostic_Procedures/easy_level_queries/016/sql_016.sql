WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
),
ecg_telemetry_procedures AS (
  SELECT pe.hadm_id, COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%telemetry%'
  GROUP BY pe.hadm_id
)
SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th
FROM ecg_telemetry_procedures
WHERE hadm_id IN (SELECT hadm_id FROM patient_admissions);