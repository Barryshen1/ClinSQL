WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    p.anchor_age,
    p.gender,
    d.icd_code,
    d.icd_version,
    a.admission_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON a.subject_id = p.subject_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM OTHER HOSP'
    AND d.seq_num = 1  -- principal diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
indexed_with_next AS (
  SELECT 
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM 
    index_admissions
),
readmission_flag AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM 
    indexed_with_next
)
SELECT 
  AVG(readmitted_30d) AS thirty_day_readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 1000)[OFFSET(500)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 1000)[OFFSET(500)] AS median_los_not_readmitted,
  AVG(CASE WHEN los_days > 4 THEN 1.0 ELSE 0.0 END) * 100 AS percent_index_stays_over_4_days
FROM 
  readmission_flag;