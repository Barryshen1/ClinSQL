WITH cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 74 AND 84
),
admissions_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = a.subject_id 
          AND d.hadm_id = a.hadm_id
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I61%') 
            OR (d.icd_version = 9 AND d.icd_code LIKE '431%')
          )
      ) THEN 1 
      ELSE 0 
    END AS has_ich
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_patients cp ON a.subject_id = cp.subject_id
),
cases AS (
  SELECT * 
  FROM admissions_cohort 
  WHERE has_ich = 1
),
controls AS (
  SELECT * 
  FROM admissions_cohort 
  WHERE has_ich = 0
),
first72_abnormal_labs AS (
  SELECT le.hadm_id, le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN admissions_cohort ac ON le.hadm_id = ac.hadm_id
  WHERE le.charttime >= ac.admittime
    AND le.charttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL 
    AND le.flag != ''
),
instability AS (
  SELECT hadm_id, COUNT(DISTINCT itemid) AS num_abnormal_labs
  FROM first72_abnormal_labs
  GROUP BY hadm_id
),
critical_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category IN ('Coagulation', 'Hematology')
),
first72_critical_abnormal_labs AS (
  SELECT le.hadm_id, le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN admissions_cohort ac ON le.hadm_id = ac.hadm_id
  INNER JOIN critical_items ci ON le.itemid = ci.itemid
  WHERE le.charttime >= ac.admittime
    AND le.charttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL 
    AND le.flag != ''
),
critical_instability AS (
  SELECT hadm_id, COUNT(DISTINCT itemid) AS num_critical_abnormal_labs
  FROM first72_critical_abnormal_labs
  GROUP BY hadm_id
),
cases_with_instability AS (
  SELECT 
    c.*, 
    COALESCE(i.num_abnormal_labs, 0) AS num_abnormal_labs,
    COALESCE(ci.num_critical_abnormal_labs, 0) AS num_critical_abnormal_labs
  FROM cases c
  LEFT JOIN instability i ON c.hadm_id = i.hadm_id
  LEFT JOIN critical_instability ci ON c.hadm_id = ci.hadm_id
),
controls_with_instability AS (
  SELECT 
    c.*, 
    COALESCE(i.num_abnormal_labs, 0) AS num_abnormal_labs,
    COALESCE(ci.num_critical_abnormal_labs, 0) AS num_critical_abnormal_labs
  FROM controls c
  LEFT JOIN instability i ON c.hadm_id = i.hadm_id
  LEFT JOIN critical_instability ci ON c.hadm_id = ci.hadm_id
),
quintiled_cases AS (
  SELECT *, NTILE(5) OVER (ORDER BY num_abnormal_labs ASC) AS quintile
  FROM cases_with_instability
),
quintile_summary AS (
  SELECT 
    quintile,
    COUNT(*) AS n_patients,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS mortality_rate,
    ROUND(AVG(num_abnormal_labs), 2) AS mean_instability,
    ROUND(AVG(num_critical_abnormal_labs), 2) AS mean_critical_instability
  FROM quintiled_cases
  GROUP BY quintile
  ORDER BY quintile
),
overall_comparison AS (
  SELECT 'ICH Cases' AS group_name, 
    COUNT(*) AS n_patients,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS mortality_rate,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
    ROUND(AVG(num_abnormal_labs), 2) AS mean_instability,
    ROUND(AVG(num_critical_abnormal_labs), 2) AS mean_critical_instability
  FROM cases_with_instability
  UNION ALL
  SELECT 'Controls' AS group_name, 
    COUNT(*) AS n_patients,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS mortality_rate,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
    ROUND(AVG(num_abnormal_labs), 2) AS mean_instability,
    ROUND(AVG(num_critical_abnormal_labs), 2) AS mean_critical_instability
  FROM controls_with_instability
)
SELECT * FROM (
  SELECT 'Quintile' AS report_section, 
    CAST(quintile AS STRING) AS subgroup, 
    n_patients, 
    mortality_rate, 
    mean_los_days, 
    mean_instability, 
    mean_critical_instability
  FROM quintile_summary
  UNION ALL
  SELECT 'Overall' AS report_section, 
    group_name AS subgroup, 
    n_patients, 
    mortality_rate, 
    mean_los_days, 
    mean_instability, 
    mean_critical_instability
  FROM overall_comparison
) ORDER BY CASE WHEN report_section = 'Quintile' THEN 1 ELSE 2 END, subgroup;