WITH index_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_index,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1
      AND (
        (icd_version = 9 AND icd_code LIKE '435%') 
        OR (icd_version = 10 AND icd_code LIKE 'G45%')
      )
  ) dx 
    ON a.hadm_id = dx.hadm_id
  WHERE 
    p.gender = 'M'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND a.insurance = 'Medicare'  -- Added Medicare filter
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
),

with_readmission_flag AS (
  SELECT 
    idx.*,
    CASE 
      WHEN nxt.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions idx
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` nxt
    ON idx.subject_id = nxt.subject_id
    AND nxt.hadm_id <> idx.hadm_id
    AND nxt.admittime > idx.dischtime
    AND nxt.admittime <= DATE_ADD(idx.dischtime, INTERVAL 30 DAY)
)

SELECT 
  COUNT(*) AS total_index_admissions,
  SUM(readmitted_30d) AS readmitted_count,
  ROUND(SUM(readmitted_30d) * 100.0 / COUNT(*), 2) AS readmission_rate_percent,
  ROUND(SUM(CASE WHEN los_index > 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percent_los_gt_10,
  (SELECT APPROX_QUANTILES(los_index, 100)[OFFSET(50)] 
   FROM with_readmission_flag 
   WHERE readmitted_30d = 1) AS median_los_readmitted,
  (SELECT APPROX_QUANTILES(los_index, 100)[OFFSET(50)] 
   FROM with_readmission_flag 
   WHERE readmitted_30d = 0) AS median_los_non_readmitted
FROM with_readmission_flag;