WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND di.long_title LIKE '%pulmonary embolism%'
),

lab_abnormal AS (
  SELECT 
    l.hadm_id, 
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  JOIN cohort c 
    ON l.hadm_id = c.hadm_id
  WHERE 
    l.ref_range_lower IS NOT NULL 
    AND l.ref_range_upper IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.hadm_id
),

percentile_75 AS (
  SELECT APPROX_QUANTILES(abnormal_count, 100)[OFFSET(75)] AS p75
  FROM lab_abnormal
),

high_score AS (
  SELECT 
    la.hadm_id, 
    la.abnormal_count, 
    c.hospital_expire_flag, 
    c.dischtime, 
    c.admittime
  FROM lab_abnormal la
  JOIN cohort c 
    ON la.hadm_id = c.hadm_id
  WHERE la.abnormal_count >= (SELECT p75 FROM percentile_75)
)

SELECT
  AVG(CAST(h.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
  AVG(DATETIME_DIFF(h.dischtime, h.admittime, DAY)) AS mean_los,
  AVG(h.abnormal_count) AS high_score_avg_abnormal,
  (SELECT AVG(abnormal_count) FROM lab_abnormal) AS entire_cohort_avg_abnormal
FROM high_score h;