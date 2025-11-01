WITH target_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      WHERE d_icd.hadm_id = a.hadm_id
        AND (
          (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '428%')
          OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I50%')
        )
    )
),
lab_counts AS (
  SELECT 
    ta.hadm_id,
    COUNT(*) AS count_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN target_admissions ta 
    ON le.hadm_id = ta.hadm_id
  WHERE le.flag = 'critical'
    AND le.charttime BETWEEN ta.admittime AND TIMESTAMP_ADD(ta.admittime, INTERVAL 48 HOUR)
  GROUP BY ta.hadm_id
),
threshold AS (
  SELECT 
    APPROX_QUANTILES(count_critical, 1000)[OFFSET(950)] AS threshold
  FROM lab_counts
),
high_instability AS (
  SELECT 
    lc.hadm_id
  FROM lab_counts lc
  CROSS JOIN threshold t
  WHERE lc.count_critical >= t.threshold
),
control_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 54 AND 64
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      WHERE d_icd.hadm_id = a.hadm_id
        AND (
          (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '428%')
          OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I50%')
        )
    )
),
control_lab_counts AS (
  SELECT 
    ca.hadm_id,
    COUNT(*) AS count_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN control_admissions ca 
    ON le.hadm_id = ca.hadm_id
  WHERE le.flag = 'critical'
    AND le.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
  GROUP BY ca.hadm_id
)
SELECT 
  (SELECT AVG(hospital_expire_flag) 
   FROM target_admissions 
   WHERE hadm_id IN (SELECT hadm_id FROM high_instability)) AS high_instability_mortality,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) 
   FROM target_admissions 
   WHERE hadm_id IN (SELECT hadm_id FROM high_instability)) AS high_instability_mean_los_days,
  (SELECT AVG(count_critical) 
   FROM lab_counts 
   WHERE hadm_id IN (SELECT hadm_id FROM high_instability)) AS high_instability_critical_lab_rate,
  (SELECT AVG(count_critical) 
   FROM control_lab_counts) AS control_critical_lab_rate;