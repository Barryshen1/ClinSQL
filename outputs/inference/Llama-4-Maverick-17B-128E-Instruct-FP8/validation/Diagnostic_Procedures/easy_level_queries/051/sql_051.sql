WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 41 AND 51
),
ecg_telemetry_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ecg%' OR LOWER(label) LIKE '%telemetry%' 
  OR LOWER(category) LIKE '%ecg%' OR LOWER(category) LIKE '%telemetry%'
),
ecg_telemetry_procedures AS (
  SELECT pe.subject_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN ecg_telemetry_itemids eti ON pe.itemid = eti.itemid
  WHERE pe.subject_id IN (SELECT subject_id FROM patient_filter)
  GROUP BY pe.subject_id
)
SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th
FROM ecg_telemetry_procedures;