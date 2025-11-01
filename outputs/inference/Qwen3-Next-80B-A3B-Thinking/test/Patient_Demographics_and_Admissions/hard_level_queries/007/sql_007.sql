WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admission_type = 'EMERGENCY'
    AND (di.long_title LIKE '%TIA%' OR di.long_title LIKE '%Transient Ischemic Attack%')
),
readmitted_flag AS (
  SELECT
    ia.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions ia
)
SELECT
  AVG(readmitted) AS readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) FILTER (WHERE readmitted = 0) AS median_los_non_readmitted,
  (COUNTIF(los_days > 10) * 100.0 / COUNT(*)) AS percent_stays_gt_10_days
FROM readmitted_flag;