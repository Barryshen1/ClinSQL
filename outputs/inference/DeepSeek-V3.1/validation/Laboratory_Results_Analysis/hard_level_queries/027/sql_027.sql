WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        -- ICD-10 codes for lower GI bleed
        (di.icd_version = 10 AND di.icd_code LIKE 'K92.2%') OR
        (di.icd_version = 10 AND di.icd_code LIKE 'K62.5%') OR
        -- ICD-9 codes
        (di.icd_version = 9 AND di.icd_code = '578.9') OR
        (di.icd_version = 9 AND di.icd_code = '569.3')
    )
),

labs_cohort AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    l.itemid, 
    l.valuenum, 
    l.ref_range_lower, 
    l.ref_range_upper,
    -- Flag abnormal if outside reference range (assuming inclusive bounds)
    CASE 
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 
      ELSE 0 
    END AS is_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE l.valuenum IS NOT NULL 
    AND l.ref_range_lower IS NOT NULL 
    AND l.ref_range_upper IS NOT NULL
),

instability_scores AS (
  SELECT 
    subject_id, 
    hadm_id,
    COUNT(*) AS total_labs,
    SUM(is_abnormal) AS abnormal_count,
    -- This is the instability score
    SUM(is_abnormal) AS instability_score
  FROM labs_cohort
  GROUP BY subject_id, hadm_id
),

quintiles AS (
  SELECT 
    subject_id, 
    hadm_id,
    instability_score,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM instability_scores
),

quintile_summary AS (
  SELECT 
    q.quintile,
    COUNT(DISTINCT q.subject_id) AS num_patients,
    AVG(c.los_days) AS avg_los,
    AVG(c.hospital_expire_flag) AS mortality_rate,
    SUM(lc.is_abnormal) AS total_abnormal_labs,
    COUNT(lc.is_abnormal) AS total_labs,
    SUM(lc.is_abnormal) / COUNT(lc.is_abnormal) AS abnormal_rate
  FROM quintiles q
  INNER JOIN cohort c ON q.hadm_id = c.hadm_id
  INNER JOIN labs_cohort lc ON q.hadm_id = lc.hadm_id
  GROUP BY q.quintile
),

general_inpatient_rate AS (
  SELECT 
    SUM(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS total_abnormal,
    COUNT(*) AS total_labs,
    SUM(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) / COUNT(*) AS abnormal_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE l.valuenum IS NOT NULL 
    AND l.ref_range_lower IS NOT NULL 
    AND l.ref_range_upper IS NOT NULL
    -- Only include the same lab tests that were considered in the cohort?
    AND l.itemid IN (SELECT DISTINCT itemid FROM labs_cohort)
)

SELECT 
  q.quintile,
  q.num_patients,
  q.avg_los,
  q.mortality_rate,
  q.abnormal_rate AS quintile_abnormal_rate,
  g.abnormal_rate AS general_inpatient_abnormal_rate
FROM quintile_summary q
CROSS JOIN general_inpatient_rate g
ORDER BY q.quintile;