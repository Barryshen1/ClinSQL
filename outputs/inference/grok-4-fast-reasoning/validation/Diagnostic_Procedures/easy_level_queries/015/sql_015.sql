WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age >= 45
    AND anchor_age <= 55
),
patient_cabg_counts AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT CASE 
      WHEN LOWER(d.long_title) LIKE '%coronary%' 
        AND LOWER(d.long_title) LIKE '%bypass%' 
      THEN p.icd_code 
    END) AS cabg_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  GROUP BY c.subject_id
)
SELECT 
  APPROX_QUANTILES(cabg_count, 4)[OFFSET(1)] AS p25_cabg_procedures
FROM patient_cabg_counts;