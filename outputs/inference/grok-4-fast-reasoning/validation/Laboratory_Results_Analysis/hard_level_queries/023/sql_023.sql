WITH cohort_ami AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
),
scores_ami AS (
  SELECT 
    c.*,
    COUNTIF(l.flag != '') AS instability_score
  FROM cohort_ami c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = c.subject_id 
    AND l.hadm_id = c.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, 
    c.hospital_expire_flag, c.los_days
),
all_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 90 AND 100
),
scores_all AS (
  SELECT 
    c.*,
    COUNTIF(l.flag != '') AS instability_score
  FROM all_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = c.subject_id 
    AND l.hadm_id = c.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, 
    c.hospital_expire_flag, c.los_days
),
p75_cte AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS p75_score
  FROM scores_ami
),
high_ami AS (
  SELECT sa.*
  FROM scores_ami sa
  CROSS JOIN p75_cte p
  WHERE sa.instability_score >= p.p75_score
)
SELECT 'P75 Lab-Instability Score' AS category, CAST(p75_score AS INT64) AS value
FROM p75_cte
UNION ALL
SELECT 'AMI High (>=P75) In-Hospital Mortality (%)' AS category, ROUND(AVG(hospital_expire_flag) * 100, 2) AS value
FROM high_ami
UNION ALL
SELECT 'AMI High (>=P75) Mean LOS (days)' AS category, ROUND(AVG(los_days), 2) AS value
FROM high_ami
UNION ALL
SELECT 'AMI High (>=P75) Critical Lab Rate (%)' AS category, ROUND(100.0 * COUNTIF(instability_score > 0) / COUNT(*), 2) AS value
FROM high_ami
UNION ALL
SELECT 'All Inpatients (90-100) In-Hospital Mortality (%)' AS category, ROUND(AVG(hospital_expire_flag) * 100, 2) AS value
FROM scores_all
UNION ALL
SELECT 'All Inpatients (90-100) Mean LOS (days)' AS category, ROUND(AVG(los_days), 2) AS value
FROM scores_all
UNION ALL
SELECT 'All Inpatients (90-100) Critical Lab Rate (%)' AS category, ROUND(100.0 * COUNTIF(instability_score > 0) / COUNT(*), 2) AS value
FROM scores_all
ORDER BY category;