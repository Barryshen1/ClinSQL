WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Room'
    AND d.seq_num = 1
    AND LOWER(di.long_title) LIKE '%tia%'
),
readmission_flag AS (
  SELECT *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= DATE_ADD(dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
)
SELECT
  AVG(readmitted_30d) * 100 AS thirty_day_readmission_rate_percent,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los END, 2)[OFFSET(1)] AS median_los_non_readmitted,
  AVG(CASE WHEN los > 10 THEN 1.0 ELSE 0.0 END) * 100 AS percent_index_stays_over_10_days
FROM readmission_flag;