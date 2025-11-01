WITH
-- first hospital admission per patient
first_admission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),
-- keep only the true first admissions
first_admission_only AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM first_admission
  WHERE rn = 1
),
-- admissions among those first admissions that have a stroke diagnosis
stroke_first_admissions AS (
  SELECT DISTINCT fa.subject_id, fa.hadm_id, fa.admittime, fa.dischtime
  FROM first_admission_only fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%stroke%'
),
-- first icustay per (subject_id, hadm_id)
first_icustay_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
-- join stroke first admissions to their first icustay and collect los
stroke_first_admission_iculoss AS (
  SELECT
    sfa.subject_id,
    sfa.hadm_id,
    ficu.stay_id,
    ficu.intime,
    ficu.outtime,
    ficu.los
  FROM stroke_first_admissions sfa
  JOIN first_icustay_per_admission ficu
    ON sfa.subject_id = ficu.subject_id
    AND sfa.hadm_id = ficu.hadm_id
    AND ficu.rn = 1
  WHERE ficu.los IS NOT NULL
)

SELECT
  SAFE_CAST(quantiles[OFFSET(25)] AS FLOAT64) AS p25_days,
  SAFE_CAST(quantiles[OFFSET(75)] AS FLOAT64) AS p75_days,
  SAFE_CAST(quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS FLOAT64) AS iqr_days,
  n_patients_used
FROM (
  SELECT
    APPROX_QUANTILES(los, 100) AS quantiles,
    COUNT(*) AS n_patients_used
  FROM stroke_first_admission_iculoss
);