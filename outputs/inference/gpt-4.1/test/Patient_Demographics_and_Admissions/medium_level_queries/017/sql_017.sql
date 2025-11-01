WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.discharge_location,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
)
, discharge_group AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
      WHEN LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%skilled nursing%'
        OR LOWER(discharge_location) LIKE '%nursing home%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%long term care%'
        OR LOWER(discharge_location) LIKE '%facility%'
        THEN 'facility'
      ELSE NULL
    END AS discharge_type
  FROM cohort
)
SELECT
  discharge_type,
  COUNT(*) AS n_icu_stays,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[50], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[75], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[90], 2) AS p90_los_days
FROM
  discharge_group
WHERE
  discharge_type IS NOT NULL
GROUP BY
  discharge_type
ORDER BY
  discharge_type;