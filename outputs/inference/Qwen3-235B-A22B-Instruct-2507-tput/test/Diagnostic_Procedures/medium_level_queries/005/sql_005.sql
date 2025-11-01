WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
),
stroke_diagnoses AS (
  SELECT
    da.subject_id,
    da.hadm_id,
    da.los_days,
    di.seq_num,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM patient_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON da.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I63%'
    AND da.age_at_admit BETWEEN 49 AND 59
),
procedure_counts AS (
  SELECT
    sd.hadm_id,
    sd.los_days,
    sd.diagnosis_type,
    COUNT(pi.icd_code) AS procedure_count
  FROM stroke_diagnoses sd
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON sd.hadm_id = pi.hadm_id
  GROUP BY sd.hadm_id, sd.los_days, sd.diagnosis_type
),
los_groups AS (
  SELECT
    hadm_id,
    diagnosis_type,
    procedure_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group
  FROM procedure_counts
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  los_group,
  diagnosis_type,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM los_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;