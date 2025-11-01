WITH cardiac_markers AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%troponin%' 
     OR label LIKE '%ck-mb%' 
     OR label LIKE '%myoglobin%' 
     OR label LIKE '%bnp%'
),
acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Approximate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
    AND (d.icd_code LIKE 'I20%' 
         OR d.icd_code LIKE 'I21%' 
         OR d.icd_code LIKE 'I22%' 
         OR d.icd_code LIKE 'I24%')
),
lab_events AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    -- Calculate deviation from reference range
    CASE 
      WHEN le.valuenum < le.ref_range_lower THEN le.ref_range_lower - le.valuenum
      WHEN le.valuenum > le.ref_range_upper THEN le.valuenum - le.ref_range_upper
      ELSE 0 
    END AS deviation
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cardiac_markers cm ON le.itemid = cm.itemid
  JOIN acs_admissions aa ON le.hadm_id = aa.hadm_id
  WHERE le.charttime BETWEEN aa.admittime AND aa.admittime + INTERVAL 48 HOUR
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
instability_scores AS (
  SELECT 
    aa.hadm_id,
    aa.age_at_admission,
    aa.hospital_expire_flag,
    aa.admittime,
    aa.dischtime,
    MAX(le.deviation) AS instability_score
  FROM acs_admissions aa
  LEFT JOIN lab_events le ON aa.hadm_id = le.hadm_id
  GROUP BY 
    aa.hadm_id, 
    aa.age_at_admission, 
    aa.hospital_expire_flag, 
    aa.admittime, 
    aa.dischtime
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100) [OFFSET(90)] AS p90
  FROM instability_scores
  WHERE instability_score IS NOT NULL
),
group_a AS (
  SELECT 
    'ACS_high_instability' AS group_name,
    AVG(hospital_expire_flag) AS mortality,
    AVG(UNIX_SECONDS(dischtime - admittime) / 86400.0) AS mean_los,
    -- Critical-lab rate: % with ≥1 abnormal lab
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0 END) AS critical_lab_rate
  FROM instability_scores, percentile
  WHERE instability_score >= p90
),
group_b AS (
  SELECT 
    'General_inpatients' AS group_name,
    AVG(hospital_expire_flag) AS mortality,
    AVG(UNIX_SECONDS(dischtime - admittime) / 86400.0) AS mean_los,
    -- Critical-lab rate for random sample
    (SELECT 
        COUNT(DISTINCT a.hadm_id) * 1.0 / COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
     LEFT JOIN lab_events le ON a.hadm_id = le.hadm_id
     WHERE le.deviation > 0
       AND a.hadm_id IN (
         SELECT hadm_id 
         FROM `physionet-data.mimiciv_3_1_hosp.admissions` 
         ORDER BY RAND() 
         LIMIT 10000
       )
    ) AS critical_lab_rate
),
results AS (
  SELECT * FROM group_a
  UNION ALL
  SELECT * FROM group_b
  UNION ALL
  SELECT 
    '90th_percentile' AS group_name,
    NULL AS mortality,
    NULL AS mean_los,
    (SELECT p90 FROM percentile) AS critical_lab_rate
)
SELECT * FROM results;