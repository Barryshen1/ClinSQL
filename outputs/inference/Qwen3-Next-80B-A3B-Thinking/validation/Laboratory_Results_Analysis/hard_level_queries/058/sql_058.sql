WITH acs_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND d.icd_code IN (
          'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4',
          'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
        )
    )
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
),
all_female_40_50 AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
),
lab_abnormal_acs AS (
  SELECT 
    a.hadm_id,
    COUNT(*) AS abnormal_count
  FROM acs_cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '48' HOUR
  WHERE l.flag IS NOT NULL
  GROUP BY a.hadm_id
),
lab_abnormal_all AS (
  SELECT 
    a.hadm_id,
    COUNT(*) AS abnormal_count
  FROM all_female_40_50 a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '48' HOUR
  WHERE l.flag IS NOT NULL
  GROUP BY a.hadm_id
),
percentile AS (
  SELECT 
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY abnormal_count) AS threshold
  FROM lab_abnormal_acs
),
high_instability AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime - a.admittime AS los,
    l.abnormal_count
  FROM acs_cohort a
  JOIN lab_abnormal_acs l ON a.hadm_id = l.hadm_id
  WHERE l.abnormal_count >= (SELECT threshold FROM percentile)
),
general_inpatients AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime - a.admittime AS los,
    l.abnormal_count
  FROM all_female_40_50 a
  JOIN lab_abnormal_all l ON a.hadm_id = l.hadm_id
)
SELECT 
  'high_instability' AS group_type,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
  AVG(los) AS mean_los,
  AVG(abnormal_count) AS critical_lab_rate
FROM high_instability
UNION ALL
SELECT 
  'general_inpatients' AS group_type,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
  AVG(los) AS mean_los,
  AVG(abnormal_count) AS critical_lab_rate
FROM general_inpatients;