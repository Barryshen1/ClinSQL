WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.anchor_year,
    CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age_at_admit
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5845', '5846', '5848', '5849'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
    AND CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 61 AND 71
),
index_with_readmit AS (
  SELECT 
    *,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
      WHERE 
        ra.subject_id = ia.subject_id
        AND ra.hadm_id != ia.hadm_id
        AND ra.admittime > ia.dischtime
        AND ra.admittime < TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS has_readmission
  FROM index_adms ia
)
SELECT 
  COUNT(*) AS total_index_admissions,
  COUNTIF(has_readmission) AS num_readmitted,
  ROUND(SAFE_DIVIDE(COUNTIF(has_readmission) * 100.0, COUNT(*)), 2) AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los, 101)[OFFSET(50)] FROM index_with_readmit WHERE has_readmission = TRUE) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los, 101)[OFFSET(50)] FROM index_with_readmit WHERE has_readmission = FALSE) AS median_los_non_readmitted_days,
  ROUND(SAFE_DIVIDE(COUNTIF(los > 6) * 100.0, COUNT(*)), 2) AS pct_index_los_gt6_days
FROM index_with_readmit;