WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.los,
    ROW_NUMBER() OVER (
      PARTITION BY icu.subject_id, icu.hadm_id
      ORDER BY icu.intime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN cohort c
      ON icu.subject_id = c.subject_id
      AND icu.hadm_id = c.hadm_id
)
SELECT
  -- 25th-percentile ICU length of stay (days)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile_days
FROM
  first_icu_stays
WHERE
  rn = 1;