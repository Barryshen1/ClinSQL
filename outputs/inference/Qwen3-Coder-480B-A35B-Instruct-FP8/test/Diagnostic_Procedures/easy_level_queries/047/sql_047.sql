WITH target_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),
target_procedures AS (
  SELECT p.hadm_id, p.subject_id, p.icd_code, p.icd_version, p.seq_num
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%catheter ablation%'
     OR LOWER(d.long_title) LIKE '%cardioversion%'
),
procedure_counts AS (
  SELECT hadm_id, COUNT(DISTINCT CONCAT(subject_id, icd_code, icd_version, seq_num)) AS proc_count
  FROM target_procedures
  GROUP BY hadm_id
)
SELECT STDDEV(proc_count) AS stddev_procedures
FROM procedure_counts;