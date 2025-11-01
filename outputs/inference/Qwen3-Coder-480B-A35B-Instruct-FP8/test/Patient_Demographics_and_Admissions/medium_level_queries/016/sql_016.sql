WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      ELSE 'Other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    )
    AND a.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.transfers`
      WHERE careunit LIKE '%ICU%'
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
percentiles AS (
  SELECT
    discharge_group,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM
    cohort
  WHERE
    discharge_group IN ('Home', 'Hospice', 'Death')
  GROUP BY
    discharge_group
),
ranked AS (
  SELECT
    discharge_group,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY discharge_group ORDER BY los_days) AS percentile_rank
  FROM
    cohort
  WHERE
    discharge_group IN ('Home', 'Hospice', 'Death')
)
SELECT
  p.discharge_group,
  p.p50,
  p.p75,
  p.p90,
  p.p95,
  MAX(CASE WHEN r.los_days <= 7 THEN r.percentile_rank ELSE 0 END) * 100 AS percentile_rank_7days
FROM
  percentiles p
JOIN
  ranked r
  ON p.discharge_group = r.discharge_group
GROUP BY
  p.discharge_group, p.p50, p.p75, p.p90, p.p95
ORDER BY
  p.discharge_group;