WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = a.subject_id
          AND a2.admittime > a.dischtime
          AND a2.admittime <= DATE_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE diag.seq_num = 1
    AND p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 51 AND 61
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'Emergency'
    AND LOWER(d.long_title) LIKE '%acute pancreatitis%'
)

SELECT 
  SUM(readmitted) / NULLIF(COUNT(*), 0) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN los_days ELSE NULL END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los_days ELSE NULL END, 100)[OFFSET(50)] AS median_los_non_readmitted,
  (COUNTIF(los_days > 9) * 100.0) / NULLIF(COUNT(*), 0) AS percent_stays_gt_9_days
FROM index_admissions;