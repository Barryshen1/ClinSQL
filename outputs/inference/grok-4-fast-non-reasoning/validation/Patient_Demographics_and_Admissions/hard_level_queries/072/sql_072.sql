WITH qualifying_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance LIKE '%MEDICARE%'
),
index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.dischtime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN qualifying_patients qp ON a.subject_id = qp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND d.seq_num = CAST(1 AS INT64) 
    AND d.icd_version = 10
  WHERE a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
    AND d.icd_code LIKE 'J96.%'
  QUALIFY rn = 1  -- Earliest qualifying admission as index
),
readmissions AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.los,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ia.subject_id
          AND a2.hadm_id != ia.hadm_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
          AND a2.hospital_expire_flag = 0
      ) THEN 1 ELSE 0 
    END AS readmitted
  FROM index_admissions ia
)
SELECT 
  readmitted,
  COUNT(*) AS n_stays,
  ROUND(AVG(readmitted) * 100, 2) AS readmission_rate_pct,
  PERCENTILE_CONT(0.5) OVER (PARTITION BY readmitted ORDER BY los) AS median_los,
  ROUND(SUM(CASE WHEN los > 8 THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS pct_stays_gt_8d
FROM readmissions
GROUP BY readmitted
ORDER BY readmitted;