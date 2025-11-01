WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 63 AND 73
),
cardiac_procedures AS (
  SELECT p.subject_id, pr.hadm_id, COUNT(DISTINCT pr.icd_code) as num_procedures
  FROM patient_filter p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Heart%' OR d.long_title LIKE '%Cardiac%'
  GROUP BY p.subject_id, pr.hadm_id
)
SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th
FROM cardiac_procedures;