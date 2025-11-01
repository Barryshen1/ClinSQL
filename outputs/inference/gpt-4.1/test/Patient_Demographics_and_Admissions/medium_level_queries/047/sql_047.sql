WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (
      LOWER(a.admission_location) LIKE '%transfer%'
      OR LOWER(a.admission_location) LIKE '%other hospital%'
    )
),
icu_los AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.discharge_location,
    c.hospital_expire_flag,
    i.stay_id,
    i.los
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON c.subject_id = i.subject_id
      AND c.hadm_id = i.hadm_id
  WHERE
    i.los IS NOT NULL
),
discharge_grouped AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%facility%'
        OR LOWER(discharge_location) LIKE '%nursing%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%skilled%'
        OR LOWER(discharge_location) LIKE '%long term%'
        OR LOWER(discharge_location) LIKE '%snf%'
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM
    icu_los
)
, stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n_stays,
    AVG(los) AS mean_los,
    STDDEV(los) AS sd_los
  FROM
    discharge_grouped
  WHERE
    discharge_group IN ('Home', 'Facility', 'Death')
  GROUP BY
    discharge_group
)
, percentiles AS (
  SELECT
    discharge_group,
    los,
    PERCENT_RANK() OVER (PARTITION BY discharge_group ORDER BY los) AS los_percentile
  FROM
    discharge_grouped
  WHERE
    discharge_group IN ('Home', 'Facility', 'Death')
)
, percentile_5day AS (
  -- Find closest LOS to 5 days for each group
  SELECT
    discharge_group,
    los,
    los_percentile,
    ABS(los - 5) AS los_diff,
    ROW_NUMBER() OVER (PARTITION BY discharge_group ORDER BY ABS(los - 5)) AS rn
  FROM
    percentiles
)
SELECT
  s.discharge_group,
  s.n_stays,
  ROUND(s.mean_los, 2) AS mean_los,
  ROUND(s.sd_los, 2) AS sd_los,
  ROUND(p.los_percentile * 100, 1) AS percentile_rank_5day
FROM
  stats s
  LEFT JOIN percentile_5day p
    ON s.discharge_group = p.discharge_group
    AND p.rn = 1
ORDER BY
  s.discharge_group
;