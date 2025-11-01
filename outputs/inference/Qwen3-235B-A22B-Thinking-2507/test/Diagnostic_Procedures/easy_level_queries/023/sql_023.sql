WITH filtered_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 82 AND 92
),
cardiac_procedure_counts AS (
  SELECT 
    fa.hadm_id,
    COUNT(DISTINCT 
      CASE 
        WHEN LOWER(d.long_title) LIKE '%cardiac%' 
          OR LOWER(d.long_title) LIKE '%heart%' 
          OR LOWER(d.long_title) LIKE '%coronary%' 
          OR LOWER(d.long_title) LIKE '%myocardial%' 
          OR LOWER(d.long_title) LIKE '%aortic%' 
          OR LOWER(d.long_title) LIKE '%valve%' 
          THEN p.icd_code 
        ELSE NULL 
      END
    ) AS cardiac_procedure_count
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON fa.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  GROUP BY fa.hadm_id
)
SELECT 
  APPROX_QUANTILES(cardiac_procedure_count, 100)[OFFSET(25)] AS percentile_25
FROM cardiac_procedure_counts;