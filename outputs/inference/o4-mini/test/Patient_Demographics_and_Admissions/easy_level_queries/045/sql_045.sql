WITH pneumonia_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING (icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
),
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
    JOIN pneumonia_admissions pa
      ON a.subject_id = pa.subject_id
     AND a.hadm_id    = pa.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN eligible_admissions ea
      ON icu.subject_id = ea.subject_id
     AND icu.hadm_id    = ea.hadm_id
)
SELECT
  -- 25th percentile of first ICU length of stay (days)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile
FROM
  first_icu_stays
WHERE
  rn = 1;