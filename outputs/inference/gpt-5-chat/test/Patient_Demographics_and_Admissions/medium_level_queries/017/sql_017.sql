WITH cohort AS (
  SELECT DISTINCT adm.subject_id,
         adm.hadm_id,
         adm.admittime,
         adm.dischtime,
         adm.discharge_location,
         adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.subject_id = icu.subject_id
   AND adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, cohort_with_los AS (
  SELECT *,
         TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
         CASE
           WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
           WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
           ELSE 'Facility'
         END AS discharge_category
  FROM cohort
)
SELECT discharge_category,
       ROUND(AVG(los_days), 2) AS mean_los_days,
       ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
       ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
       ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days
FROM cohort_with_los
GROUP BY discharge_category
ORDER BY discharge_category;