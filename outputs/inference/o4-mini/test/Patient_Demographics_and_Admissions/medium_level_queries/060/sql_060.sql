WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND UPPER(a.admission_location) = 'EMERGENCY ROOM'
    -- ensure we only keep the three outcomes of interest
    AND (
      a.hospital_expire_flag = 1
      OR UPPER(a.discharge_location) LIKE '%HOSPICE%'
      OR UPPER(a.discharge_location) LIKE 'HOME%'
    )
)
SELECT
  discharge_outcome,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV_POP(los_days), 2) AS sd_los,
  ROUND(
    100.0 * SAFE_DIVIDE(
      SUM(IF(los_days <= 10, 1, 0)),
      COUNT(*)
    ), 2
  ) AS pct_los_leq_10
FROM
  cohort
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;