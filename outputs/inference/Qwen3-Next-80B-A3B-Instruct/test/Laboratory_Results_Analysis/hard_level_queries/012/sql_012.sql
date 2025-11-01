WITH amicohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),

generalcohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
    )
),

lab_critical AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    COUNT(CASE 
      WHEN le.valuenum IS NOT NULL 
        AND le.ref_range_lower IS NOT NULL 
        AND le.ref_range_upper IS NOT NULL 
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        AND le.charttime >= c.admittime 
        AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
      THEN 1 
    END) AS critical_lab_count_72h
  FROM (
    SELECT subject_id, hadm_id, admittime FROM amicohort
    UNION ALL
    SELECT subject_id, hadm_id, admittime FROM generalcohort
  ) c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
    ON le.itemid = dl.itemid
  WHERE le.charttime IS NOT NULL
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.admittime
),

cohort_stats AS (
  SELECT 
    CASE 
      WHEN ac.subject_id IS NOT NULL THEN 'AMI'
      ELSE 'General'
    END AS cohort,
    AVG(lc.critical_lab_count_72h) AS mean_critical_labs,
    PERCENTILE_CONT(lc.critical_lab_count_72h, 0.75) WITHIN GROUP (ORDER BY lc.critical_lab_count_72h) AS p75_lab_instability,
    PERCENTILE_CONT(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0, 0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS median_los_days,
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM (
    SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag FROM amicohort
    UNION ALL
    SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag FROM generalcohort
  ) a
  LEFT JOIN lab_critical lc ON a.subject_id = lc.subject_id AND a.hadm_id = lc.hadm_id
  LEFT JOIN amicohort ac ON a.subject_id = ac.subject_id AND a.hadm_id = ac.hadm_id
  GROUP BY cohort
)

SELECT 
  MAX(CASE WHEN cohort = 'AMI' THEN p75_lab_instability END) AS p75_lab_instability_ami,
  MAX(CASE WHEN cohort = 'AMI' THEN mean_critical_labs END) AS mean_critical_labs_ami,
  MAX(CASE WHEN cohort = 'General' THEN mean_critical_labs END) AS mean_critical_labs_general,
  MAX(CASE WHEN cohort = 'AMI' THEN median_los_days END) AS median_los_days_ami,
  MAX(CASE WHEN cohort = 'General' THEN median_los_days END) AS median_los_days_general,
  MAX(CASE WHEN cohort = 'AMI' THEN mortality_rate END) AS mortality_rate_ami,
  MAX(CASE WHEN cohort = 'General' THEN mortality_rate END) AS mortality_rate_general
FROM cohort_stats;