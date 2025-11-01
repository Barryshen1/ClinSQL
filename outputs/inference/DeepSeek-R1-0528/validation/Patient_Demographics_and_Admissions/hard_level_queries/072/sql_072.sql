WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '518.81') OR
      (diag.icd_version = 10 AND diag.icd_code IN (
        'J96.00', 'J96.01', 'J96.02', 'J96.20', 'J96.21', 'J96.22', 
        'J96.90', 'J96.91', 'J96.92'
      ))
    )
  WHERE 
    p.gender = 'F'
    AND adm.admission_location = 'TRANSFER FROM SKILLED NURSING FACILITY'
    AND adm.insurance = 'Medicare'
    AND adm.hospital_expire_flag = 0
),
filtered_index AS (
  SELECT *
  FROM index_admissions
  WHERE age_at_admission BETWEEN 77 AND 87
),
with_readmission_flag AS (
  SELECT 
    fi.*,
    CASE WHEN n.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM filtered_index fi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` n
    ON fi.subject_id = n.subject_id
    AND n.admittime > fi.dischtime
    AND n.admittime <= TIMESTAMP_ADD(fi.dischtime, INTERVAL 30 DAY)
    AND n.hadm_id != fi.hadm_id
)
SELECT
  COUNT(*) AS total_index_admissions,
  SUM(readmitted_30d) AS readmitted_count,
  AVG(readmitted_30d) * 100 AS readmission_rate_percent,
  APPROX_QUANTILES(IF(readmitted_30d=1, los, NULL), 100)[SAFE_OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted_30d=0, los, NULL), 100)[SAFE_OFFSET(50)] AS median_los_not_readmitted,
  SAFE_DIVIDE(COUNTIF(los > 8) * 100.0, COUNT(*)) AS percent_los_gt_8
FROM with_readmission_flag;