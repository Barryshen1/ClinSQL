WITH pneumonia_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
    AND d.icd_version = 10  -- MIMIC-IV uses ICD-10 for most recent data
),
first_admission AS (
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM pneumonia_admissions
  ) ranked
  WHERE rn = 1
),
first_icu_stay AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(i.outtime, i.intime, DAY) AS los_days
  FROM first_admission fa
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON fa.hadm_id = i.hadm_id
  WHERE i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),
first_icu_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    intime,
    outtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS icu_rn
  FROM first_icu_stay
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER () AS p25_los_days
FROM first_icu_per_admission
WHERE icu_rn = 1
LIMIT 1;