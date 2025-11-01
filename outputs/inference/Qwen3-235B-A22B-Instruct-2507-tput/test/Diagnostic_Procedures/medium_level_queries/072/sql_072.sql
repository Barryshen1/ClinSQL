WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    a.admittime,
    a.dischtime,
    -- Length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    -- Classify diagnosis as primary or secondary
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_position
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 52 AND 62
    AND d.icd_version = 10
    AND d.icd_code LIKE 'K85%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
filtered_admissions AS (
  SELECT *
  FROM patient_admissions
  WHERE los_days BETWEEN 1 AND 8
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd
  GROUP BY hadm_id
),
admission_summary AS (
  SELECT
    fa.hadm_id,
    fa.diagnosis_position,
    fa.los_days,
    pc.procedure_count
  FROM filtered_admissions fa
  LEFT JOIN procedure_counts pc
    ON fa.hadm_id = pc.hadm_id
  -- Use LEFT JOIN to include admissions with zero procedures
)
SELECT
  diagnosis_position,
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM admission_summary
GROUP BY diagnosis_position, los_group
ORDER BY diagnosis_position, los_group;