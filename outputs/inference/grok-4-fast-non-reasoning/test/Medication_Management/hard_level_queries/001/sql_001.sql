WITH eligible_admissions AS (
  -- First admission per patient matching criteria
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code = '427.5') OR 
      (d.icd_version = 'ICD-10' AND d.icd_code = 'I46')
    )
),

med_scores AS (
  -- Count distinct poe_id (unique orders) in first 7 days
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    COUNT(DISTINCT pres.poe_id) AS score
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON ea.subject_id = pres.subject_id 
    AND ea.hadm_id = pres.hadm_id
    AND pres.starttime >= ea.admittime
    AND pres.starttime < TIMESTAMP_ADD(ea.admittime, INTERVAL 7 DAY)
  WHERE ea.rn = 1  -- Only first admission (INT64 comparison)
  GROUP BY ea.subject_id, ea.hadm_id
),

readmissions AS (
  -- Flag patients with 30-day readmission (excluding deaths)
  SELECT 
    ea.subject_id AS orig_subject_id,
    COUNT(DISTINCT read_a.hadm_id) > 0 AS has_readmission
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` read_a
    ON ea.subject_id = read_a.subject_id
    AND read_a.hadm_id != ea.hadm_id
    AND read_a.admittime > ea.dischtime
    AND read_a.admittime <= TIMESTAMP_ADD(ea.dischtime, INTERVAL 30 DAY)
    AND ea.hospital_expire_flag = 0  -- No readmit if died in index
  WHERE ea.rn = 1
  GROUP BY ea.subject_id
)

SELECT 
  quintile,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(score), 2) AS avg_score,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS in_hospital_mortality_pct,
  ROUND((SUM(CASE WHEN has_readmission = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 2) AS readmission_30d_pct
FROM (
  SELECT 
    ms.*,
    ea.dischtime,
    ea.hospital_expire_flag,
    DATETIME_DIFF(ea.dischtime, ea.admittime, DAY) + 
    EXTRACT(HOUR FROM (ea.dischtime - ea.admittime)) / 24.0 AS los_days,
    r.has_readmission,
    NTILE(5) OVER (ORDER BY ms.score ASC) AS quintile
  FROM med_scores ms
  INNER JOIN eligible_admissions ea 
    ON ms.subject_id = ea.subject_id AND ms.hadm_id = ea.hadm_id AND ea.rn = 1
  LEFT JOIN readmissions r 
    ON ms.subject_id = r.orig_subject_id
)
GROUP BY quintile
ORDER BY quintile;