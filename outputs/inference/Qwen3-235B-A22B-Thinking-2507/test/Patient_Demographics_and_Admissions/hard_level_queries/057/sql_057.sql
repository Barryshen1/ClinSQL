WITH index_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 60 AND 70
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND a.dischtime IS NOT NULL
    AND (
      LOWER(dd.long_title) LIKE '%urinary tract infection%'
      OR LOWER(dd.long_title) LIKE '%cystitis%'
      OR LOWER(dd.long_title) LIKE '%pyelonephritis%'
    )
),
index_with_readmission AS (
  SELECT 
    ia.*,
    IF(EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
      WHERE 
        a.subject_id = ia.subject_id
        AND a.admittime > ia.dischtime
        AND a.admittime <= ia.dischtime + INTERVAL '30' DAY
        AND a.hadm_id != ia.hadm_id
    ), 1, 0) AS readmitted_30d
  FROM index_admissions ia
),
overall AS (
  SELECT 
    COUNT(*) AS total,
    SUM(readmitted_30d) AS readmitted_count
  FROM index_with_readmission
),
breakdown AS (
  SELECT
    readmitted_30d,
    COUNT(*) AS n,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_gt9
  FROM index_with_readmission
  GROUP BY readmitted_30d
)
SELECT 
  (SELECT readmitted_count * 1.0 / total FROM overall) AS readmission_rate,
  readmitted_30d,
  median_los,
  percent_los_gt9
FROM breakdown;