WITH aki_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute kidney injury%'
),
female_elderly_aki AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    aki_admissions aki
    ON a.subject_id = aki.subject_id
    AND a.hadm_id = aki.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
first_icu_stays AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.los,
    ROW_NUMBER() OVER (
      PARTITION BY fe.subject_id, fe.hadm_id
      ORDER BY ic.intime
    ) AS rn
  FROM
    female_elderly_aki fe
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON fe.subject_id = ic.subject_id
    AND fe.hadm_id = ic.hadm_id
)
SELECT
  -- Approximate 25th percentile of ICU length of stay (days)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM
  first_icu_stays
WHERE
  rn = 1;