WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime + INTERVAL 12 HOUR
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age, p.gender
  HAVING SUM(CASE 
      WHEN (dic.icd_version = 10 AND dic.long_title LIKE '%Type 2 diabetes mellitus%')
        OR (dic.icd_version = 9 AND dic.long_title LIKE '%Diabetes mellitus, type 2%') 
      THEN 1 ELSE 0 END) >= 1
    AND SUM(CASE 
      WHEN (dic.icd_version = 10 AND dic.long_title LIKE '%Heart failure%')
        OR (dic.icd_version = 9 AND dic.long_title LIKE '%Heart failure%') 
      THEN 1 ELSE 0 END) >= 1
),
glp1_prescriptions AS (
  SELECT DISTINCT
    p.hadm_id,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE LOWER(p.drug) IN (
    'liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide', 'albiglutide',
    'victoza', 'ozempic', 'byetta', 'trulicity', 'adlyxin', 'tanzeum'
  )
),
first_12h AS (
  SELECT COUNT(DISTINCT g.hadm_id) AS count_first_12h
  FROM glp1_prescriptions g
  INNER JOIN cohort c ON g.hadm_id = c.hadm_id
  WHERE g.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR
),
last_12h AS (
  SELECT COUNT(DISTINCT g.hadm_id) AS count_last_12h
  FROM glp1_prescriptions g
  INNER JOIN cohort c ON g.hadm_id = c.hadm_id
  WHERE g.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime
),
total_cohort AS (
  SELECT COUNT(*) AS total_patients
  FROM cohort
)
SELECT
  ROUND(100.0 * f.count_first_12h / t.total_patients, 2) AS percent_first_12h,
  ROUND(100.0 * l.count_last_12h / t.total_patients, 2) AS percent_last_12h,
  ROUND(100.0 * (l.count_last_12h - f.count_first_12h) / t.total_patients, 2) AS net_change_percent
FROM first_12h f
CROSS JOIN last_12h l
CROSS JOIN total_cohort t;