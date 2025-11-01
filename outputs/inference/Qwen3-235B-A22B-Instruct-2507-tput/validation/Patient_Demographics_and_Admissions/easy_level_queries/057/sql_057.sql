WITH stroke_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%stroke%'
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- Only males
),
patients_with_first_stroke_admission AS (
  SELECT
    fa.subject_id,
    MIN(fa.admittime) AS first_admittime
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fa.hadm_id = di.hadm_id
  JOIN stroke_icd s ON di.icd_code = s.icd_code AND di.icd_version = s.icd_version
  WHERE fa.age_at_admit BETWEEN 46 AND 56
  GROUP BY fa.subject_id
),
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_with_first_stroke_admission pfsa
    ON i.subject_id = pfsa.subject_id
)
SELECT
  PERCENTILE_CONT(los, 0.75) OVER() - PERCENTILE_CONT(los, 0.25) OVER() AS iqr_los
FROM first_icu_stays
WHERE rn = 1
LIMIT 1;