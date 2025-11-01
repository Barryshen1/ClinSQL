WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),
procedure_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM eligible_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE dproc.long_title LIKE '%mechanical%' 
    AND dproc.long_title LIKE '%circulatory%'
  GROUP BY p.subject_id
)
SELECT
  STDDEV(distinct_procedure_count) AS stddev_distinct_procedures_per_patient
FROM procedure_counts;