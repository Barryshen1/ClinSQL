WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%hemorrhag%'
    -- Only stays 1–7 days
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 7
),
us_counts AS (
  SELECT
    pc.hadm_id,
    COUNT(*) AS us_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pc.icd_code = dp.icd_code
     AND pc.icd_version = dp.icd_version
    -- Identify ultrasounds by keyword
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY
    pc.hadm_id
)
SELECT
  CASE
    WHEN ca.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN ca.los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS stay_category,
  ROUND(AVG(COALESCE(us.us_count, 0)), 2) AS mean_ultrasounds_per_admission,
  MIN(COALESCE(us.us_count, 0)) AS min_ultrasounds_per_admission,
  MAX(COALESCE(us.us_count, 0)) AS max_ultrasounds_per_admission
FROM
  cohort_admissions AS ca
  LEFT JOIN us_counts AS us
    ON ca.hadm_id = us.hadm_id
GROUP BY
  stay_category
ORDER BY
  stay_category;