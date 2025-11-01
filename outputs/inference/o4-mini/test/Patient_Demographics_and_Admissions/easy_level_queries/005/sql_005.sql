WITH dialysis_admissions AS (
  -- Admissions where a dialysis procedure (ICD-9 39.95) occurred
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    icd_version = 9
    AND icd_code = '39.95'
  GROUP BY
    subject_id,
    hadm_id
),

eligible_patients AS (
  -- Female patients aged 77–87 with a dialysis admission
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN dialysis_admissions d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),

first_icu_stays AS (
  -- For each patient, find the first ICU stay (by intime) in that dialysis admission
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.los,
    ROW_NUMBER() OVER (
      PARTITION BY icu.subject_id
      ORDER BY icu.intime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN eligible_patients ep
      ON icu.subject_id = ep.subject_id
     AND icu.hadm_id = ep.hadm_id
)

-- Compute the 25th and 75th percentiles of LOS (IQR bounds) using APPROX_QUANTILES
SELECT
  quantiles[OFFSET(25)] AS los_p25_days,
  quantiles[OFFSET(75)] AS los_p75_days
FROM (
  SELECT
    APPROX_QUANTILES(los, 100) AS quantiles
  FROM
    first_icu_stays
  WHERE
    rn = 1
);