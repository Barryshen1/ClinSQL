WITH medicine_hadm AS (
  SELECT DISTINCT s.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services` s
  WHERE UPPER(s.curr_service) LIKE 'MED%'
),
filtered_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN medicine_hadm mh
    ON a.hadm_id = mh.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%REHAB%'
        OR UPPER(discharge_location) LIKE '%SNF%'
        OR UPPER(discharge_location) LIKE '%NURS%'
        OR UPPER(discharge_location) LIKE '%HOSP%'
        OR UPPER(discharge_location) LIKE '%FACILITY%'
        OR UPPER(discharge_location) LIKE '%SKILLED%'
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM filtered_admissions
)
SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS los_p25,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS los_p50,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_p75,
  APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS los_p90,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_le_10_days
FROM categorized
WHERE discharge_category IN ('Home', 'Facility', 'Death')
GROUP BY discharge_category
ORDER BY discharge_category;