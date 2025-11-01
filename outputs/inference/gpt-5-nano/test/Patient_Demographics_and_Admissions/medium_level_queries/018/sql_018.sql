WITH
  pat_filtered AS (
    SELECT DISTINCT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE (LOWER(p.gender) IN ('m','male') OR p.gender = 'M')
      AND p.anchor_age BETWEEN 43 AND 53
  ),
  adm_filtered AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.discharge_location,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN pat_filtered AS pf ON a.subject_id = pf.subject_id
    WHERE LOWER(a.admission_type) LIKE '%transfer%'
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
      AND a.dischtime > a.admittime
  ),
  classified AS (
    SELECT
      CASE
        WHEN LOWER(discharge_location) LIKE '%home%' THEN 'home'
        WHEN hospital_expire_flag = 1 THEN 'in_hospital_death'
        WHEN LOWER(discharge_location) LIKE '%facility%' OR
             LOWER(discharge_location) LIKE '%care%' OR
             LOWER(discharge_location) LIKE '%skilled%' THEN 'facility'
        ELSE NULL
      END AS discharge_group,
      TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
    FROM adm_filtered
  )
SELECT
  discharge_group,
  -- Median LOS
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
  -- 25th and 75th percentiles (IQR bounds)
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los_days,
  -- Percent with LOS <= 10 days
  100 * SUM(CASE WHEN los_days <= 10.0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_le_10_days
FROM classified
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;