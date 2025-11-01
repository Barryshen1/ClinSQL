WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
ecg_procedures AS (
  SELECT proc.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dicd
    ON proc.icd_code = dicd.icd_code
    AND proc.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%electrocardiogram%' OR
    LOWER(dicd.long_title) LIKE '%ecg%' OR
    LOWER(dicd.long_title) LIKE '%ekg%' OR
    LOWER(dicd.long_title) LIKE '%telemetry%' OR
    LOWER(dicd.long_title) LIKE '%cardiac monitor%' OR
    LOWER(dicd.long_title) LIKE '%holter%' OR
    LOWER(dicd.long_title) LIKE '%cardiac rhythm%'
),
procedure_counts AS (
  SELECT 
    c.subject_id,
    COUNT(ecg.subject_id) AS num_procedures  -- COUNT(ecg.subject_id) = 0 if no match
  FROM cohort c
  LEFT JOIN ecg_procedures ecg
    ON c.subject_id = ecg.subject_id
  GROUP BY c.subject_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25
FROM procedure_counts;