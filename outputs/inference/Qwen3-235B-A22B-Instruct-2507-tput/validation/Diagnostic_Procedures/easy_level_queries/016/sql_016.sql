WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  -- Calculate age at admission
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
),
admissions_ecg AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS count_procedures
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN eligible_patients e ON a.subject_id = e.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
    ON a.hadm_id = h.hadm_id
    AND (h.hcpcs_cd LIKE '930%' OR h.hcpcs_cd LIKE '932%')
  GROUP BY a.hadm_id
)
SELECT
  APPROX_QUANTILES(COALESCE(count_procedures, 0), 100)[OFFSET(75)] AS ecg_procedures_75th_percentile
FROM admissions_ecg;