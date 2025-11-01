WITH dvt_hadm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%venous thrombosis%'
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime,
         p.gender, p.anchor_age,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN dvt_hadm AS dv
    ON a.subject_id = dv.subject_id AND a.hadm_id = dv.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),
lab_events AS (
  SELECT e.subject_id, e.hadm_id, e.charttime, e.valuenum,
         e.ref_range_lower, e.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS e
  JOIN cohort AS c
    ON e.subject_id = c.subject_id AND e.hadm_id = c.hadm_id
  WHERE e.charttime BETWEEN c.admittime
                     AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
lis_per_adm AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(*) AS total_lab,
         SUM(CASE
               WHEN e.valuenum IS NOT NULL
                    AND e.ref_range_lower IS NOT NULL
                    AND e.ref_range_upper IS NOT NULL
                    AND (e.valuenum < e.ref_range_lower OR e.valuenum > e.ref_range_upper)
                 THEN 1 ELSE 0
             END) AS lis_count
  FROM cohort c
  LEFT JOIN lab_events e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
lis_per_adm_with_rate AS (
  SELECT la.subject_id, la.hadm_id, la.total_lab, la.lis_count,
         CASE WHEN la.total_lab > 0
              THEN CAST(la.lis_count AS FLOAT64) / la.total_lab
              ELSE NULL
         END AS abnormal_rate
  FROM lis_per_adm AS la
),
-- 95th percentile of LIS (calculated without WITHIN GROUP)
p95 AS (
  SELECT lis_count AS p95_lis
  FROM (
    SELECT lis_count,
           ROW_NUMBER() OVER (ORDER BY lis_count) AS rn,
           COUNT(*) OVER () AS total
    FROM lis_per_adm
  )
  WHERE rn = CAST(CEILING(0.95 * total) AS INT64)
  LIMIT 1
),
high_lis AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime,
         l.total_lab, l.lis_count, l.abnormal_rate,
         (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
         CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS death_flag
  FROM lis_per_adm_with_rate AS l
  JOIN cohort AS a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN p95
    ON l.lis_count >= p95.p95_lis
),
summary AS (
  SELECT
     CAST(AVG(death_flag) * 100 AS FLOAT64) AS mortality_rate_high_lis_pct,
     AVG(los_days) AS mean_los_days_high_lis,
     AVG(abnormal_rate) AS mean_abnormal_rate_high_lis
  FROM high_lis
),
all_inpatients_summary AS (
  SELECT AVG(abnormal_rate) AS mean_abnormal_rate_all_inpatients
  FROM lis_per_adm_with_rate
)

SELECT '95th_percentile_of_LIS' AS metric, p95_lis AS value
FROM p95
UNION ALL
SELECT 'Mortality_rate_high_LIS_pct', mortality_rate_high_lis_pct
FROM summary
UNION ALL
SELECT 'Mean_LOS_high_LIS_days', mean_los_days_high_lis
FROM summary
UNION ALL
SELECT 'Mean_Abnormal_rate_high_LIS', mean_abnormal_rate_high_lis
FROM summary
UNION ALL
SELECT 'Mean_Abnormal_rate_all_inpatients', mean_abnormal_rate_all_inpatients
FROM all_inpatients_summary
UNION ALL
SELECT 'High_LIS_admission_count', COUNT(*) FROM high_lis
UNION ALL
SELECT 'Total_admissions_in_cohort', COUNT(*) FROM lis_per_adm_with_rate
ORDER BY metric;