WITH patient_subset AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),
procedures AS (
  SELECT p.subject_id, pr.hadm_id, pr.icd_code
  FROM patient_subset p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Cardioversion%' OR d.long_title LIKE '%Catheter ablation%'
),
procedure_counts AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_procedures
  FROM procedures
  GROUP BY hadm_id
)

SELECT STDDEV(num_procedures) AS sd_procedures
FROM procedure_counts;