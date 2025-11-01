WITH admissions_with_diagnosis AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE d.long_title LIKE '%acute pancreatitis%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND a.dischtime IS NOT NULL
),
procedures_per_admission AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
los_categories AS (
  SELECT
    a.hadm_id,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group
  FROM admissions_with_diagnosis a
  LEFT JOIN procedures_per_admission p ON a.hadm_id = p.hadm_id
)
SELECT
  los_group,
  COUNT(hadm_id) AS patient_count,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM los_categories
WHERE los_group IS NOT NULL
GROUP BY los_group;