WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND LOWER(did.long_title) LIKE '%gastrointestinal hemorrhage%'
    AND NOT (LOWER(did.long_title) LIKE '%upper%')
),
readmitted_flags AS (
  SELECT 
    ia.*,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
      WHERE 
        r.subject_id = ia.subject_id
        AND r.hadm_id != ia.hadm_id
        AND r.admittime > ia.dischtime
        AND r.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS has_readmission
  FROM index_adms ia
)
SELECT 
  COUNT(*) AS total_index_admissions,
  SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END) AS num_readmitted,
  ROUND(SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmitted_flags WHERE has_readmission) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmitted_flags WHERE NOT has_readmission) AS median_los_not_readmitted_days,
  ROUND(SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_los_gt6_overall
FROM readmitted_flags;