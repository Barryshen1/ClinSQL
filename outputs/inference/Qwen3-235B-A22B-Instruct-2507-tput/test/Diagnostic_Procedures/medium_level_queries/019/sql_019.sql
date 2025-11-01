WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND a.dischtime IS NOT NULL
),
pancreatitis_admissions AS (
  SELECT DISTINCT
    pa.hadm_id,
    pa.los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'K85%'
),
procedure_counts AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    COUNT(pi.hadm_id) AS procedure_count
  FROM pancreatitis_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pa.hadm_id = pi.hadm_id
  GROUP BY pa.hadm_id, pa.los_days
),
los_groups AS (
  SELECT
    hadm_id,
    procedure_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1–4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5–7 days'
    END AS los_group
  FROM procedure_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  COUNT(*) AS patient_count,
  ROUND(AVG(procedure_count), 2) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM los_groups
GROUP BY los_group
ORDER BY los_group;