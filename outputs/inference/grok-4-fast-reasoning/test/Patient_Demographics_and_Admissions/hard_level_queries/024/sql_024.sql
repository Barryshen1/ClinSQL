WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    a.insurance,
    a.admission_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I63%'
    )
),
cohort AS (
  SELECT 
    *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
        WHERE 
          r.subject_id = i.subject_id
          AND r.hadm_id != i.hadm_id
          AND r.admittime > i.dischtime
          AND r.admittime <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM index_adms i
)
SELECT 
  (SUM(readmitted) * 1.0 / COUNT(*)) * 100 AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM cohort WHERE readmitted = 1) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM cohort WHERE readmitted = 0) AS median_los_nonreadmitted_days,
  (SUM(CASE WHEN los > 5 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) * 100 AS pct_stays_gt5days
FROM cohort;