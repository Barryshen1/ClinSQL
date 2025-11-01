WITH target_procedures AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    icd_version = 10 AND
    (
      long_title LIKE '%ablation%' OR 
      long_title LIKE '%cardioversion%'
    )
),
patient_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT t.icd_code) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN target_procedures t
    ON proc.icd_code = t.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
  GROUP BY p.subject_id
)
SELECT
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS q75
FROM patient_counts;