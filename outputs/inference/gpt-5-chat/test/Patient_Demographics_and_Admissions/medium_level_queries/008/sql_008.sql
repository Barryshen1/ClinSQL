WITH med_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE UPPER(curr_service) = 'MED'
  ) s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND UPPER(a.admission_type) != 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
stats_by_group AS (
  SELECT
    discharge_group,
    APPROX_QUANTILES(los_days, 100) AS quantiles,
    COUNT(*) AS total_count,
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS count_le_7,
    AVG(los_days) AS mean_los
  FROM (
    SELECT
      CASE
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_group,
      los_days
    FROM med_inpatients
  )
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  mean_los,
  quantiles[50] AS median_los,
  quantiles[75] AS p75_los,
  quantiles[90] AS p90_los,
  100 * count_le_7 / total_count AS pct_rank_7_days
FROM stats_by_group
ORDER BY discharge_group;