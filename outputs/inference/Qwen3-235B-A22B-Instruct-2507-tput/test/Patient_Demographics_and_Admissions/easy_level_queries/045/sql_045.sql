WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.admittime IS NOT NULL
),
ranked_admissions AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS adm_seq
  FROM first_admissions
),
first_adm_only AS (
  SELECT * FROM ranked_admissions WHERE adm_seq = 1
),
pneumonia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
    AND icd_version = 10
),
pneumonia_first_adm AS (
  SELECT DISTINCT
    fa.*
  FROM first_adm_only fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  JOIN pneumonia_codes pc
    ON di.icd_code = pc.icd_code
  WHERE di.icd_version = 10
),
first_icu_stay AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.gender,
    fa.age_at_admit,
    ist.los,
    ROW_NUMBER() OVER (PARTITION BY fa.subject_id ORDER BY ist.intime) AS icu_seq
  FROM pneumonia_first_adm fa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ist
    ON fa.hadm_id = ist.hadm_id
),
first_icu_only AS (
  SELECT 
    los,
    gender,
    age_at_admit
  FROM first_icu_stay
  WHERE icu_seq = 1
)
SELECT
  APPROX_QUANTILES(los, 1000)[OFFSET(250)] AS icu_los_25th_percentile
FROM first_icu_only
WHERE
  gender = 'M'
  AND age_at_admit >= 51
  AND age_at_admit <= 61;