WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
),

procedure_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    (icd_version = 9 AND icd_code IN ('8855', '8856', '3601', '3602', '3605', '3606', '3607', '3609'))
    OR 
    (icd_version = 10 
     AND LOWER(long_title) LIKE '%coronary%' 
     AND (
       LOWER(long_title) LIKE '%angiography%' 
       OR LOWER(long_title) LIKE '%angioplasty%' 
       OR LOWER(long_title) LIKE '%stent%' 
       OR LOWER(long_title) LIKE '%intervention%'
     )
    )
),

procedure_counts AS (
  SELECT 
    pa.hadm_id,
    COUNT(filtered_pci.seq_num) AS procedure_count
  FROM patient_admissions pa
  LEFT JOIN (
    SELECT 
      pci.hadm_id,
      pci.seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pci
    INNER JOIN procedure_codes pc
      ON pci.icd_code = pc.icd_code 
      AND pci.icd_version = pc.icd_version
  ) AS filtered_pci
    ON pa.hadm_id = filtered_pci.hadm_id
  GROUP BY pa.hadm_id
)

SELECT 
  APPROX_QUANTILES(COALESCE(procedure_count, 0), 1000)[OFFSET(750)] AS p75_procedure_count
FROM procedure_counts;