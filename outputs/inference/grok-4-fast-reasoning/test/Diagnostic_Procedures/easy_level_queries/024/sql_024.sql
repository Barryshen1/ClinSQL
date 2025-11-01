WITH relevant_subjects AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
admissions_with_counts AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN LOWER(d.long_title) LIKE '%coronary%' 
        AND (
          LOWER(d.long_title) LIKE '%angiograph%' 
          OR LOWER(d.long_title) LIKE '%arteriograph%' 
          OR LOWER(d.long_title) LIKE '%angioplast%' 
          OR LOWER(d.long_title) LIKE '%stent%' 
          OR LOWER(d.long_title) LIKE '%percutaneous coronary%' 
          OR LOWER(d.long_title) LIKE '%pci%'
        ) 
      THEN p.icd_code 
    END) AS num_distinct_procs
  FROM relevant_subjects rs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON rs.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
    ON a.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  GROUP BY a.hadm_id
)
SELECT APPROX_QUANTILES(num_distinct_procs, 100)[OFFSET(75)] AS p75th_percentile
FROM admissions_with_counts;