WITH cabg_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    MIN(a.admittime) OVER (PARTITION BY p.subject_id) AS first_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      -- ICD-9 codes for CABG
      (proc.icd_version = 9 AND proc.icd_code LIKE '36.1%') 
      OR
      -- ICD-10 codes for CABG
      (proc.icd_version = 10 AND proc.icd_code LIKE '021[0-9A-Z]%')
    )
),
first_cabg AS (
  SELECT 
    subject_id,
    hadm_id,
    anchor_age
  FROM cabg_admissions
  WHERE admittime = first_admittime
),
icu_los_per_admission AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.anchor_age,
    SUM(i.los) AS total_icu_los_days
  FROM first_cabg f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON f.hadm_id = i.hadm_id
  GROUP BY f.subject_id, f.hadm_id, f.anchor_age
)
SELECT 
  AVG(total_icu_los_days) AS mean_icu_los_days,
  COUNT(*) AS num_patients
FROM icu_los_per_admission;