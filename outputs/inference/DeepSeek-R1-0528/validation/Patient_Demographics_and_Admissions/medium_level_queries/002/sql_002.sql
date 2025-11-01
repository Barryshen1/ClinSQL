WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit,
    -- Define discharge groups
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN (
    -- Subquery to get first service per admission
    SELECT
      s.hadm_id,
      s.curr_service AS first_service
    FROM
      `physionet-data.mimiciv_3_1_hosp.services` s
    INNER JOIN (
      SELECT
        hadm_id,
        MIN(transfertime) AS first_transfertime
      FROM
        `physionet-data.mimiciv_3_1_hosp.services`
      GROUP BY
        hadm_id
    ) s0
      ON s.hadm_id = s0.hadm_id
      AND s.transfertime = s0.first_transfertime
  ) s1
    ON a.hadm_id = s1.hadm_id
  WHERE
    p.gender = 'M'
    AND s1.first_service = 'Medicine'
    -- Filter age 59-69 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
)

SELECT
  discharge_group,
  COUNT(*) AS total_admissions,
  AVG(los_days) AS mean_los,
  -- Percentiles (25th, 50th, 75th, 90th)
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
  -- Percentage with LOS <= 10 days
  ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(*), 2) AS pct_leq_10_days
FROM
  cohort
GROUP BY
  discharge_group
ORDER BY
  discharge_group;