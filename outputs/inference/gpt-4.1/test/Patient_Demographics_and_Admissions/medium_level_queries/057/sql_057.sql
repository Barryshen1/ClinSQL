WITH base AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.los,
    pat.gender,
    pat.anchor_age,
    adm.discharge_location,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
)
, outcome_labeled AS (
  SELECT
    stay_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM base
)
, percentiles AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(los, 6) AS los_quantiles, -- 6 quantiles: 0, 0.5, 0.75, 0.9, 0.95, 1
    ROUND(100 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*),1) AS pct_los_le_7d
  FROM
    outcome_labeled
  WHERE
    discharge_outcome IS NOT NULL
  GROUP BY
    discharge_outcome
)
SELECT
  discharge_outcome,
  n_stays,
  ROUND(los_quantiles[OFFSET(1)],2) AS p50_los,
  ROUND(los_quantiles[OFFSET(2)],2) AS p75_los,
  ROUND(los_quantiles[OFFSET(3)],2) AS p90_los,
  ROUND(los_quantiles[OFFSET(4)],2) AS p95_los,
  pct_los_le_7d
FROM
  percentiles
ORDER BY
  discharge_outcome;