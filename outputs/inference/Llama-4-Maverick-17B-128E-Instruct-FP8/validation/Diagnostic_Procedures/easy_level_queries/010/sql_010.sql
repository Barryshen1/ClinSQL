WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 84 AND 94
),
patient_admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN target_patients p ON a.subject_id = p.subject_id
),
echocardiography_procedures AS (
  SELECT h.subject_id, h.hadm_id, h.chartdate, d.short_description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%echocardiogram%' OR LOWER(d.long_description) LIKE '%echocardiogram%'
),
procedure_counts AS (
  SELECT subject_id, COUNT(DISTINCT hadm_id || '-' || chartdate) as num_procedures
  FROM echocardiography_procedures
  GROUP BY subject_id
)

SELECT MAX(num_procedures) as max_procedures
FROM procedure_counts;