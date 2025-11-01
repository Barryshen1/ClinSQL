WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN di.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(dicd.long_title) LIKE '%ischemic stroke%'
      OR di.icd_code LIKE 'I63%'
    )
),
procedure_counts AS (
  SELECT
    isa.hadm_id,
    isa.diagnosis_type,
    isa.los,
    COUNT(pi.seq_num) AS num_procedures
  FROM ischemic_stroke_admissions isa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON isa.hadm_id = pi.hadm_id
  GROUP BY isa.hadm_id, isa.diagnosis_type, isa.los
)
SELECT
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'other'
  END AS los_group,
  diagnosis_type,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM procedure_counts
WHERE los BETWEEN 1 AND 8
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;