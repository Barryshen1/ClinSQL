WITH relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 86 AND 96
),
procedure_counts AS (
  SELECT p.subject_id, COUNT(DISTINCT proc.icd_code) as num_procedures
  FROM relevant_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE d_proc.long_title LIKE '%catheter ablation%' OR d_proc.long_title LIKE '%cardioversion%'
  GROUP BY p.subject_id
)
SELECT STDDEV(num_procedures) as sd_procedures
FROM procedure_counts;