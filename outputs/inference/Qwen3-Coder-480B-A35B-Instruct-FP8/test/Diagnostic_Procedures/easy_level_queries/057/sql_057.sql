WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),
cardiac_cath_procedures AS (
  SELECT p.subject_id, p.hadm_id, p.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac catheterization%'
    AND d.long_title LIKE '%Diagnostic%'
),
procedure_counts AS (
  SELECT fp.subject_id, COUNT(ccp.seq_num) AS proc_count
  FROM filtered_patients fp
  JOIN cardiac_cath_procedures ccp
    ON fp.subject_id = ccp.subject_id
  GROUP BY fp.subject_id
)
SELECT MIN(proc_count) AS min_procedures_per_patient
FROM procedure_counts;