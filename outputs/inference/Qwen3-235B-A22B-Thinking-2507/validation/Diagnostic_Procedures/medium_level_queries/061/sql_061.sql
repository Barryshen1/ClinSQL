WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    DATE(a.admittime) AS admission_date,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id 
          AND d.seq_num = 1
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '584%') 
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          )
      ) THEN 'primary'
      ELSE 'secondary'
    END AS aki_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '584%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
),
imaging_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(long_description) LIKE '%x-ray%'
     OR LOWER(long_description) LIKE '%ct%'
     OR LOWER(long_description) LIKE '%mri%'
     OR LOWER(long_description) LIKE '%ultrasound%'
     OR LOWER(long_description) LIKE '%radiograph%'
     OR LOWER(long_description) LIKE '%scan%'
     OR LOWER(long_description) LIKE '%imaging%'
),
time_windows AS (
  SELECT '1-3' AS time_window, 0 AS start_offset, 2 AS end_offset
  UNION ALL
  SELECT '4-7', 3, 6
),
imaging_counts AS (
  SELECT 
    ba.hadm_id,
    ba.aki_type,
    tw.time_window,
    COUNT(ic.code) AS imaging_count
  FROM base_admissions ba
  CROSS JOIN time_windows tw
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON ba.hadm_id = h.hadm_id
    AND h.chartdate BETWEEN DATE_ADD(ba.admission_date, INTERVAL tw.start_offset DAY) 
                        AND DATE_ADD(ba.admission_date, INTERVAL tw.end_offset DAY)
  LEFT JOIN imaging_codes ic 
    ON h.hcpcs_cd = ic.code
  GROUP BY ba.hadm_id, ba.aki_type, tw.time_window
)
SELECT
  aki_type,
  time_window,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(750)] - APPROX_QUANTILES(imaging_count, 1000)[OFFSET(250)] AS iqr
FROM imaging_counts
GROUP BY aki_type, time_window
ORDER BY aki_type, time_window;