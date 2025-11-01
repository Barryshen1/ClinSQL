WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code LIKE '410%') OR 
      (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  ) diag 
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pt.gender = 'F' 
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 90 AND 100
),

lab_abnormal AS (
  SELECT 
    c.hadm_id,
    COUNTIF(labe.flag = 'abnormal') AS abnormal_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` labe
    ON c.hadm_id = labe.hadm_id
    AND labe.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

p75_value AS (
  SELECT 
    APPROX_QUANTILES(abnormal_count, 100)[OFFSET(75)] AS p75
  FROM lab_abnormal
),

cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(la.abnormal_count, 0) AS abnormal_count,
    (SELECT p75 FROM p75_value) AS p75
  FROM cohort c
  LEFT JOIN lab_abnormal la
    ON c.hadm_id = la.hadm_id
),

cohort_groups AS (
  SELECT 
    hadm_id,
    'Entire Cohort' AS group_name,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    abnormal_count
  FROM cohort_with_score
  UNION ALL
  SELECT 
    hadm_id,
    'High Instability' AS group_name,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    abnormal_count
  FROM cohort_with_score
  WHERE abnormal_count >= p75
)

SELECT 
  (SELECT p75 FROM p75_value) AS lab_instability_score_75th_percentile,
  group_name,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(abnormal_count) AS critical_lab_rate
FROM cohort_groups
GROUP BY group_name
ORDER BY group_name DESC;