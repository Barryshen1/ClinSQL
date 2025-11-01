WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN INT64(86) AND INT64(96)
    AND anchor_age IS NOT NULL
),
procedure_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  WHERE proc.icd_version = '10'
    AND UPPER(proc.icd_code) IN ('0H53%', '5A1212Z', '5A1222Z')
  GROUP BY p.subject_id
)
SELECT 
  STDDEV(num_distinct_procedures) AS sd_procedures
FROM procedure_counts;