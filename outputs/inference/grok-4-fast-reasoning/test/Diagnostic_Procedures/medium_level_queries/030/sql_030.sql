WITH bleed_codes AS (
  SELECT icd_code FROM UNNEST([
    -- Partial list of common ICD-9 codes for upper GI bleeding (expand as needed)
    '530.7', '530.82',
    '531.00', '531.01', '531.10', '531.11', '531.20', '531.21', '531.40', '531.41', '531.60', '531.61',
    '532.00', '532.01', '532.10', '532.11', '532.20', '532.21', '532.40', '532.41', '532.60', '532.61',
    '533.00', '533.01', '533.10', '533.11', '533.20', '533.21', '533.40', '533.41', '533.60', '533.61',
    '534.00', '534.01', '534.10', '534.11', '534.20', '534.21', '534.40', '534.41', '534.60', '534.61',
    '535.01', '535.21', '535.41', '535.51', '535.61',
    '537.83', '578.0',
    -- Partial list of common ICD-10 codes for upper GI bleeding (expand as needed)
    'K25.0', 'K25.2', 'K25.4', 'K25.6',
    'K26.0', 'K26.2', 'K26.4', 'K26.6',
    'K27.0', 'K27.2', 'K27.4', 'K27.6',
    'K22.6', 'K22.8', 'I85.01', 'I85.11', 'I98.31'
  ]) AS icd_code
),
cohort AS (
  SELECT 
    a.hadm_id,
    p.gender,
    (EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age) AS approx_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN bleed_codes b 
    ON d.icd_code = b.icd_code
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age) BETWEEN 53 AND 63
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
procedure_counts AS (
  SELECT 
    c.hadm_id,
    c.los_days,
    CASE 
      WHEN c.los_days <= 4 THEN '1-4 days' 
      ELSE '5-8 days' 
    END AS stay_bucket,
    COUNT(pi.seq_num) AS num_diagnostic_procedures  -- Count of procedure entries (assumes all are diagnostic in context)
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON c.hadm_id = pi.hadm_id
  GROUP BY c.hadm_id, c.los_days, stay_bucket
)
SELECT 
  stay_bucket,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(3)] AS p75
FROM procedure_counts
GROUP BY stay_bucket
ORDER BY stay_bucket;