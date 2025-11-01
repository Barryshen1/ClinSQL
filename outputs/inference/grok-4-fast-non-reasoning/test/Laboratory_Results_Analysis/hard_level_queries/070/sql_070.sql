WITH common_labs AS (
  -- Define common lab itemids for instability score (example set; extend as needed)
  SELECT itemid
  FROM UNNEST([50868, 50862, 50970, 50912, 51265, 51222, 51279, 5131, 50878, 51237,
               51274, 50893, 50960, 50931, 51221, 50882, 50971, 51248, 51202, 50861]) AS itemid
),
target_cohort AS (
  -- Target: Males 40-50 with hemorrhagic stroke
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND p.anchor_age <= 200  -- Valid age
    AND icd.icd_version = 10
    AND (icd.icd_code LIKE 'I60%' OR icd.icd_code LIKE 'I61%')  -- Hemorrhagic stroke
    AND d.seq_num = 1  -- Primary diagnosis
    AND a.admittime >= '2008-01-01'  -- Data availability
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age  -- Dedup multiple strokes
),
lab_abnormalities AS (
  -- Abnormal labs in 72h window for target cohort
  SELECT 
    tc.hadm_id,
    tc.subject_id,
    le.itemid,
    MAX(CASE 
      WHEN le.flag = 1 OR 
           (le.valuenum IS NOT NULL AND (
             (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
             (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
           ))
      THEN 1 ELSE 0 
    END) AS has_abnormal
  FROM target_cohort tc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON tc.subject_id = le.subject_id AND tc.hadm_id = le.hadm_id
  INNER JOIN common_labs cl ON le.itemid = cl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= tc.admittime
    AND le.charttime < TIMESTAMP_ADD(tc.admittime, INTERVAL 3 DAY)
  GROUP BY tc.hadm_id, tc.subject_id, le.itemid
),
instability_scores AS (
  SELECT 
    tc.*,
    COUNT(DISTINCT CASE WHEN la.has_abnormal = 1 THEN la.itemid END) AS instability_score
  FROM target_cohort tc
  LEFT JOIN lab_abnormalities la ON tc.hadm_id = la.hadm_id AND tc.subject_id = la.subject_id
  GROUP BY tc.subject_id, tc.hadm_id, tc.admittime, tc.dischtime, tc.hospital_expire_flag, tc.anchor_age, tc.los_days
),
quartiles AS (
  SELECT 
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    los_days,
    hospital_expire_flag
  FROM instability_scores
),
quartile_summary AS (
  -- Stratified outcomes for target cohort
  SELECT 
    quartile,
    COUNT(*) AS n,
    AVG(los_days) AS avg_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate
  FROM quartiles
  GROUP BY quartile
),
general_cohort AS (
  -- General: All males 40-50
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    le.itemid,
    le.valuenum,
    le.flag,
    le.ref_range_lower,
    le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id AND p.subject_id = le.subject_id
  INNER JOIN common_labs cl ON le.itemid = cl.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND p.anchor_age <= 200
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 3 DAY)
    AND a.admittime >= '2008-01-01'
),
general_abnormal_rates AS (
  -- Per-lab abnormal rates in general cohort
  SELECT 
    gc.itemid,
    di.label,
    AVG(CASE 
      WHEN gc.flag = 1 OR 
           (gc.valuenum IS NOT NULL AND (
             (gc.ref_range_lower IS NOT NULL AND gc.valuenum < gc.ref_range_lower) OR
             (gc.ref_range_upper IS NOT NULL AND gc.valuenum > gc.ref_range_upper)
           ))
      THEN 1.0 ELSE 0 
    END) AS general_abnormal_rate
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON gc.itemid = di.itemid
  GROUP BY gc.itemid, di.label
  HAVING general_abnormal_rate > 0  -- Only labs with some abnormality
)
-- Combine results: Quartile summary and general rates (use UNION for single table output; add type column)
SELECT 'quartile_summary' AS result_type, CAST(quartile AS STRING) AS key, CAST(n AS STRING) AS value1, 
       CAST(avg_los_days AS STRING) AS value2, CAST(mortality_rate AS STRING) AS value3, NULL AS extra
FROM quartile_summary
UNION ALL
SELECT 'general_rates' AS result_type, CAST(itemid AS STRING) AS key, label AS value1, 
       CAST(general_abnormal_rate AS STRING) AS value2, NULL, NULL
FROM general_abnormal_rates
ORDER BY result_type, key;