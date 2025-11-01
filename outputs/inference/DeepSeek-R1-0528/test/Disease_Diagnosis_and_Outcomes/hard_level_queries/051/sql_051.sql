WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
),

pancreatitis AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE 
    (d.icd_version = 9 AND d.icd_code = '5770') 
    OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
),

diag_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT CONCAT(icd_code, CAST(icd_version AS STRING))) AS total_diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

major_complications_list AS (
  SELECT '51881' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '51882', 9 UNION ALL
  SELECT '51884', 9 UNION ALL
  SELECT '5185', 9 UNION ALL
  SELECT '7991', 9 UNION ALL
  SELECT '5845', 9 UNION ALL
  SELECT '5846', 9 UNION ALL
  SELECT '5847', 9 UNION ALL
  SELECT '5848', 9 UNION ALL
  SELECT '5849', 9 UNION ALL
  SELECT '78550', 9 UNION ALL
  SELECT '78551', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT '78559', 9 UNION ALL
  SELECT '9980', 9 UNION ALL
  SELECT '5772', 9 UNION ALL
  SELECT '99591', 9 UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT 'J96.00', 10 UNION ALL
  SELECT 'J96.01', 10 UNION ALL
  SELECT 'J96.02', 10 UNION ALL
  SELECT 'J96.20', 10 UNION ALL
  SELECT 'J96.21', 10 UNION ALL
  SELECT 'J96.22', 10 UNION ALL
  SELECT 'J96.9', 10 UNION ALL
  SELECT 'J96.90', 10 UNION ALL
  SELECT 'J96.91', 10 UNION ALL
  SELECT 'J96.92', 10 UNION ALL
  SELECT 'R09.2', 10 UNION ALL
  SELECT 'N17.0', 10 UNION ALL
  SELECT 'N17.1', 10 UNION ALL
  SELECT 'N17.2', 10 UNION ALL
  SELECT 'N17.8', 10 UNION ALL
  SELECT 'N17.9', 10 UNION ALL
  SELECT 'R57.0', 10 UNION ALL
  SELECT 'R57.1', 10 UNION ALL
  SELECT 'R57.8', 10 UNION ALL
  SELECT 'R57.9', 10 UNION ALL
  SELECT 'T81.10', 10 UNION ALL
  SELECT 'T81.11', 10 UNION ALL
  SELECT 'T81.12', 10 UNION ALL
  SELECT 'T81.19', 10 UNION ALL
  SELECT 'K86.3', 10 UNION ALL
  SELECT 'A41.9', 10 UNION ALL
  SELECT 'R65.20', 10 UNION ALL
  SELECT 'R65.21', 10
),

major_comp AS (
  SELECT 
    d.hadm_id,
    COUNT(DISTINCT CONCAT(d.icd_code, CAST(d.icd_version AS STRING))) AS major_complication_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN major_complications_list m
    ON d.icd_code = m.icd_code AND d.icd_version = m.icd_version
  GROUP BY d.hadm_id
),

cohort_data AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.hospital_expire_flag,
    COALESCE(dc.total_diagnosis_count, 0) AS total_diagnosis_count,
    COALESCE(mc.major_complication_count, 0) AS major_complication_count,
    COALESCE(dc.total_diagnosis_count, 0) + 5 * COALESCE(mc.major_complication_count, 0) AS risk_score,
    CASE 
      WHEN p.hospital_expire_flag = 0 THEN 
        DATETIME_DIFF(p.dischtime, p.admittime, DAY) 
    END AS los_survivor
  FROM pancreatitis p
  LEFT JOIN diag_counts dc
    ON p.hadm_id = dc.hadm_id
  LEFT JOIN major_comp mc
    ON p.hadm_id = mc.hadm_id
),

with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM cohort_data
),

quartile_agg AS (
  SELECT 
    risk_quartile,
    COUNT(*) AS num_patients,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(CASE WHEN major_complication_count > 0 THEN 1.0 ELSE 0.0 END) AS major_complication_rate,
    APPROX_QUANTILES(los_survivor, 100)[OFFSET(50)] AS median_survivor_los
  FROM with_quartiles
  GROUP BY risk_quartile
),

overall AS (
  SELECT 
    NULL AS risk_quartile,
    COUNT(*) AS num_patients,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(CASE WHEN major_complication_count > 0 THEN 1.0 ELSE 0.0 END) AS major_complication_rate,
    APPROX_QUANTILES(los_survivor, 100)[OFFSET(50)] AS median_survivor_los
  FROM with_quartiles
)

SELECT 
  CAST(risk_quartile AS STRING) AS risk_quartile,
  num_patients,
  in_hospital_mortality_rate,
  major_complication_rate,
  median_survivor_los
FROM quartile_agg
UNION ALL
SELECT 
  'Overall' AS risk_quartile,
  num_patients,
  in_hospital_mortality_rate,
  major_complication_rate,
  median_survivor_los
FROM overall
ORDER BY risk_quartile NULLS LAST;