WITH stroke_cohort AS (
  -- Male, 49-59, inpatient with ischemic stroke (any I63)
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
),
control_cohort AS (
  -- Male, 49-59, inpatient WITHOUT ischemic stroke
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.icd_version = 10 AND d.icd_code LIKE 'I63%'
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND d.hadm_id IS NULL  -- No I63
),
lab_instability AS (
  -- Compute score for stroke cohort: count abnormal labs in first 72h
  SELECT sc.hadm_id,
         COUNT(le.labevent_id) AS instability_score,
         sc.admittime,
         sc.dischtime,
         sc.hospital_expire_flag
  FROM stroke_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sc.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.flag = 'abnormal'
    AND le.charttime >= sc.admittime
    AND le.charttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 72 HOUR)
    AND li.fluid = 'Blood'  -- Blood labs only
    AND li.category != 'ERROR'
  GROUP BY sc.hadm_id, sc.admittime, sc.dischtime, sc.hospital_expire_flag
),
stroke_with_score AS (
  -- Include hadm_id with 0 score if no labs
  SELECT hadm_id, instability_score, admittime, dischtime, hospital_expire_flag
  FROM lab_instability
  UNION ALL
  SELECT sc.hadm_id, 0 AS instability_score, sc.admittime, sc.dischtime, sc.hospital_expire_flag
  FROM stroke_cohort sc
  LEFT JOIN lab_instability li ON sc.hadm_id = li.hadm_id
  WHERE li.hadm_id IS NULL
),
p75_score AS (
  SELECT PERCENTILE_CONT(0.75) OVER() AS p75_instability
  FROM stroke_with_score
  LIMIT 1
),
high_instability_stroke AS (
  SELECT sws.*
  FROM stroke_with_score sws
  CROSS JOIN p75_score p75
  WHERE sws.instability_score >= p75.p75_instability
),
high_group_stats AS (
  SELECT 
    'High-Instability Stroke' AS group_name,
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(instability_score) AS mean_instability_score
  FROM high_instability_stroke
),
control_lab_instability AS (
  -- Mirror for controls
  SELECT cc.hadm_id,
         COUNT(le.labevent_id) AS instability_score,
         cc.admittime,
         cc.dischtime,
         cc.hospital_expire_flag
  FROM control_cohort cc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cc.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.flag = 'abnormal'
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
    AND li.fluid = 'Blood'
    AND li.category != 'ERROR'
  GROUP BY cc.hadm_id, cc.admittime, cc.dischtime, cc.hospital_expire_flag
),
control_with_score AS (
  SELECT hadm_id, instability_score, admittime, dischtime, hospital_expire_flag
  FROM control_lab_instability
  UNION ALL
  SELECT cc.hadm_id, 0 AS instability_score, cc.admittime, cc.dischtime, cc.hospital_expire_flag
  FROM control_cohort cc
  LEFT JOIN control_lab_instability cli ON cc.hadm_id = cli.hadm_id
  WHERE cli.hadm_id IS NULL
),
control_group_stats AS (
  SELECT 
    'Controls' AS group_name,
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(instability_score) AS mean_instability_score
  FROM control_with_score
),
high_critical_labs AS (
  -- Abnormal rates for key labs in high group (first 72h)
  SELECT 
    'Sodium' AS lab_type,
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%sodium%' THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Potassium',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%potassium%' THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Creatinine',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%creatinine%' THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'WBC',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND (LOWER(li.label) LIKE '%wbc%' OR LOWER(li.label) LIKE '%leukocytes%') THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Hemoglobin',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%hemoglobin%' THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Glucose',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%glucose%' THEN his.hadm_id END) * 100.0 / COUNT(DISTINCT his.hadm_id) AS abnormal_rate_pct
  FROM high_instability_stroke his
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON his.hadm_id = le.hadm_id
    AND le.charttime >= his.admittime
    AND le.charttime < TIMESTAMP_ADD(his.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
),
control_critical_labs AS (
  -- Mirror for controls
  SELECT 
    'Sodium' AS lab_type,
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%sodium%' THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Potassium',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%potassium%' THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Creatinine',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%creatinine%' THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'WBC',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND (LOWER(li.label) LIKE '%wbc%' OR LOWER(li.label) LIKE '%leukocytes%') THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Hemoglobin',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%hemoglobin%' THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
  UNION ALL
  SELECT 'Glucose',
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND LOWER(li.label) LIKE '%glucose%' THEN cc.hadm_id END) * 100.0 / COUNT(DISTINCT cc.hadm_id) AS abnormal_rate_pct
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cc.hadm_id = le.hadm_id
    AND le.charttime >= cc.admittime
    AND le.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON le.itemid = li.itemid
),
summary AS (
  SELECT 
    p75.p75_instability AS p75th_percentile_instability_score,
    hgs.group_name AS high_group_name,
    hgs.n_patients AS high_n_patients,
    hgs.mean_los_days AS high_mean_los_days,
    hgs.mortality_rate AS high_mortality_rate,
    hgs.mean_instability_score AS high_mean_instability_score,
    cgs.n_patients AS control_n_patients,
    cgs.mean_los_days AS control_mean_los_days,
    cgs.mortality_rate AS control_mortality_rate,
    cgs.mean_instability_score AS control_mean_instability_score,
    NULL AS lab_type,
    NULL AS high_stroke_rate_pct,
    NULL AS control_rate_pct
  FROM p75_score p75
  CROSS JOIN high_group_stats hgs
  CROSS JOIN control_group_stats cgs
),
lab_comparison AS (
  SELECT 
    NULL AS p75th_percentile_instability_score,
    NULL AS high_group_name,
    NULL AS high_n_patients,
    NULL AS high_mean_los_days,
    NULL AS high_mortality_rate,
    NULL AS high_mean_instability_score,
    NULL AS control_n_patients,
    NULL AS control_mean_los_days,
    NULL AS control_mortality_rate,
    NULL AS control_mean_instability_score,
    cl.lab_type,
    cl.abnormal_rate_pct AS high_stroke_rate_pct,
    ccl.abnormal_rate_pct AS control_rate_pct
  FROM high_critical_labs cl
  LEFT JOIN control_critical_labs ccl ON cl.lab_type = ccl.lab_type
)
SELECT * FROM summary
UNION ALL
SELECT * FROM lab_comparison
ORDER BY CASE WHEN lab_type IS NULL THEN 0 ELSE 1 END, lab_type;