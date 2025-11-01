WITH population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Age at admission: 48-58 years
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
    -- Type 2 diabetes (ICD-10 E11.*)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'
    )
    -- Heart failure (ICD-10 I50.*)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),
admissions_with_flags AS (
  SELECT 
    p.hadm_id,
    MAX(CASE 
          WHEN e.charttime >= p.admittime 
            AND e.charttime <= TIMESTAMP_ADD(p.admittime, INTERVAL 12 HOUR) 
          THEN 1 ELSE 0 
        END) AS received_first_12h,
    MAX(CASE 
          WHEN e.charttime >= TIMESTAMP_SUB(p.dischtime, INTERVAL 12 HOUR) 
            AND e.charttime <= p.dischtime 
          THEN 1 ELSE 0 
        END) AS received_final_12h
  FROM population p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON p.hadm_id = e.hadm_id
    AND e.charttime IS NOT NULL
    AND (
      LOWER(e.medication) LIKE '%exenatide%' 
      OR LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
    )
  GROUP BY p.hadm_id
),
counts AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(received_first_12h) AS count_first_12h,
    SUM(received_final_12h) AS count_final_12h
  FROM admissions_with_flags
)
SELECT
  total_admissions,
  count_first_12h,
  count_final_12h,
  SAFE_DIVIDE(count_first_12h, total_admissions) * 100 AS percent_first_12h,
  SAFE_DIVIDE(count_final_12h, total_admissions) * 100 AS percent_final_12h,
  (SAFE_DIVIDE(count_final_12h, total_admissions) - SAFE_DIVIDE(count_first_12h, total_admissions)) * 100 AS net_change
FROM counts;