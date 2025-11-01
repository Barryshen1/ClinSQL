WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Readmission flag: check if there is any subsequent admission within 30 days
    (SELECT 1 
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
     WHERE a2.subject_id = a.subject_id 
       AND a2.hadm_id <> a.hadm_id 
       AND a2.admittime > a.dischtime 
       AND a2.admittime <= DATE_ADD(a.dischtime, INTERVAL 30 DAY)
     LIMIT 1) AS readmitted_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'  -- Corrected: use p.gender instead of a.gender
    AND a.insurance LIKE '%Medicare%'
    AND a.admission_location = 'SNF'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 68 AND 78  -- Corrected age calculation
    AND d.seq_num = 1
    AND dd.long_title LIKE '%UTI%'
    AND a.dischtime IS NOT NULL
),
readmission_stats AS (
  SELECT 
    AVG(CAST(readmitted_flag AS FLOAT64)) * 100 AS readmission_rate,
    -- For median LOS by readmission status
    (SELECT APPROX_QUANTILES(los, 1000)[OFFSET(500)] 
     FROM cohort 
     WHERE readmitted_flag = 1) AS median_los_readmitted,
    (SELECT APPROX_QUANTILES(los, 1000)[OFFSET(500)] 
     FROM cohort 
     WHERE readmitted_flag = 0) AS median_los_non_readmitted,
    -- Percent of stays >6 days
    AVG(CASE WHEN los > 6 THEN 1.0 ELSE 0 END) * 100 AS percent_stays_gt6
  FROM cohort
)
SELECT * FROM readmission_stats;