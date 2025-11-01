WITH cabg_procedures AS (
  -- Identify CABG procedures using ICD codes
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE (p.icd_version = 9 AND d.long_title LIKE '%coronary artery bypass%') 
     OR (p.icd_version = 10 AND (d.icd_code LIKE '021%' OR d.icd_code LIKE '022%'))
  UNION DISTINCT
  -- Identify CABG procedures using HCPCS codes
  SELECT DISTINCT h.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON h.hcpcs_cd = d.code
  WHERE d.code IN ('33533')  -- Example HCPCS code for CABG
),
patient_cabg_count AS (
  SELECT p.subject_id, COUNT(c.subject_id) AS cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN cabg_procedures c ON p.subject_id = c.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
  GROUP BY p.subject_id
)
SELECT APPROX_QUANTILES(cabg_count, 100)[OFFSET(25)] AS percentile_25th
FROM patient_cabg_count;