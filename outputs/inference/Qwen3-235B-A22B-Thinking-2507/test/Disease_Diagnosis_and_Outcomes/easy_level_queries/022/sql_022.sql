WITH filtered_admissions AS (
  SELECT 
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND d.seq_num = 1
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '434%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 71 AND 81
),
quantiles AS (
  SELECT 
    PERCENTILE_CONT(los, 0.25) OVER (ORDER BY los) AS q1,
    PERCENTILE_CONT(los, 0.75) OVER (ORDER BY los) AS q3
  FROM filtered_admissions
  LIMIT 1
)
SELECT q3 - q1 AS iqr
FROM quantiles;