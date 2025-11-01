SELECT 
  PERCENTILE_CONT(0.5) OVER (ORDER BY los_days) AS median_los_days
FROM (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 
       AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
    AND a.dischtime > a.admittime
)
LIMIT 1;