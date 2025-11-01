WITH base_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 38 AND 48
),
admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN base_patients bp ON a.subject_id = bp.subject_id
),
ami_hadms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%') 
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),
control_hadms AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM admissions a
  WHERE NOT EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
      AND ((d.icd_version = 9 AND d.icd_code LIKE '410%') 
           OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%'))
  )
),
lab_scores_ami AS (
  SELECT 
    ah.subject_id, ah.hadm_id, ah.admittime, ah.dischtime, ah.hospital_expire_flag,
    TIMESTAMP_DIFF(ah.dischtime, ah.admittime, HOUR) / 24.0 AS los_days,
    COUNT(le.labevent_id) AS instability_score
  FROM ami_hadms ah
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = ah.subject_id 
    AND le.hadm_id = ah.hadm_id
    AND le.charttime >= ah.admittime
    AND le.charttime < TIMESTAMP_ADD(ah.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY ah.subject_id, ah.hadm_id, ah.admittime, ah.dischtime, ah.hospital_expire_flag
),
ami_with_quartile AS (
  SELECT *, NTILE(4) OVER (ORDER BY instability_score ASC) AS quartile
  FROM lab_scores_ami
),
ami_quartiles AS (
  SELECT 
    'quartile' AS result_type,
    quartile,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
    COUNT(*) AS num_patients,
    CAST(NULL AS FLOAT64) AS critical_lab_rate_pct,
    CAST(NULL AS FLOAT64) AS avg_instability_score,
    CAST(NULL AS STRING) AS group_type
  FROM ami_with_quartile
  GROUP BY quartile
),
ami_overall AS (
  SELECT 
    'comparison' AS result_type,
    CAST(NULL AS INT64) AS quartile,
    CAST(NULL AS FLOAT64) AS avg_los_days,
    CAST(NULL AS FLOAT64) AS mortality_pct,
    COUNT(*) AS num_patients,
    ROUND(100.0 * COUNT(CASE WHEN instability_score > 0 THEN 1 END) / COUNT(*), 2) AS critical_lab_rate_pct,
    ROUND(AVG(instability_score), 2) AS avg_instability_score,
    'AMI' AS group_type
  FROM lab_scores_ami
),
control_num_patients AS (
  SELECT COUNT(*) AS num_patients
  FROM control_hadms
),
control_total_abnormal AS (
  SELECT COUNT(*) AS total_abnormal
  FROM control_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = ch.subject_id 
    AND le.hadm_id = ch.hadm_id
    AND le.charttime >= ch.admittime
    AND le.charttime < TIMESTAMP_ADD(ch.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
),
control_num_critical AS (
  SELECT COUNT(DISTINCT ch.hadm_id) AS num_critical
  FROM control_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = ch.subject_id 
    AND le.hadm_id = ch.hadm_id
    AND le.charttime >= ch.admittime
    AND le.charttime < TIMESTAMP_ADD(ch.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
),
control_overall AS (
  SELECT 
    'comparison' AS result_type,
    CAST(NULL AS INT64) AS quartile,
    CAST(NULL AS FLOAT64) AS avg_los_days,
    CAST(NULL AS FLOAT64) AS mortality_pct,
    cp.num_patients,
    ROUND(100.0 * nc.num_critical / cp.num_patients, 2) AS critical_lab_rate_pct,
    ROUND(ta.total_abnormal * 1.0 / cp.num_patients, 2) AS avg_instability_score,
    'Control' AS group_type
  FROM control_num_patients cp
  CROSS JOIN control_total_abnormal ta
  CROSS JOIN control_num_critical nc
)
-- Combined results: Quartiles first (LOS in days, mortality %), then lab rate comparison
SELECT * FROM ami_quartiles 
UNION ALL
SELECT * FROM ami_overall 
UNION ALL
SELECT * FROM control_overall
ORDER BY result_type, 
  CASE WHEN result_type = 'quartile' THEN quartile ELSE 0 END,
  group_type;