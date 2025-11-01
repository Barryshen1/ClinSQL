WITH patient_selection AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 82 AND 92
),
admissions_for_selected_patients AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_selection p ON a.subject_id = p.subject_id
),
cardiac_procedures_per_hadm AS (
  SELECT a.hadm_id, COUNT(DISTINCT p.icd_code) as num_procedures
  FROM admissions_for_selected_patients a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25th
FROM cardiac_procedures_per_hadm;