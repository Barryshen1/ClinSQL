WITH cohort AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'hospice'
      WHEN UPPER(a.discharge_location) LIKE '%HOME%' THEN 'home'
      ELSE NULL
    END AS disp
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.subject_id = i.subject_id
     AND a.hadm_id    = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND i.stay_id IS NULL                -- exclude any ICU stays
    AND
    (
      a.hospital_expire_flag = 1
      OR UPPER(a.discharge_location) LIKE '%HOSPICE%'
      OR UPPER(a.discharge_location) LIKE '%HOME%'
    )
)
SELECT
  disp AS discharge_disposition,
  -- Compute approximate quantiles array of size 101 (0th to 100th)
  quantiles[OFFSET(50)]  AS p50_los_days,
  quantiles[OFFSET(75)]  AS p75_los_days,
  quantiles[OFFSET(90)]  AS p90_los_days,
  quantiles[OFFSET(95)]  AS p95_los_days,
  -- Percentile rank of a 7-day stay = proportion of stays <= 7 days
  SAFE_DIVIDE(
    COUNTIF(los <= 7),
    COUNT(*)
  ) AS pct_rank_7day
FROM (
  SELECT
    disp,
    los,
    APPROX_QUANTILES(los, 100) AS quantiles
  FROM
    cohort
  GROUP BY
    disp,
    los
)
GROUP BY
  disp,
  quantiles
ORDER BY
  disp;