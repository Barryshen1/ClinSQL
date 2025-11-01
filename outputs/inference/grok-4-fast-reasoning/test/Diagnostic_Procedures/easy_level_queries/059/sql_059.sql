WITH cohort_hadms AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
counts AS (
  SELECT 
    ch.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN LOWER(d.long_title) LIKE '%heart%' 
        OR LOWER(d.long_title) LIKE '%cardiac%' 
        OR LOWER(d.long_title) LIKE '%coronary%' 
      THEN proc.icd_code 
    END) AS num_distinct_cardiac
  FROM cohort_hadms ch
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON ch.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code 
    AND proc.icd_version = d.icd_version
  GROUP BY ch.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_cardiac, 4)[OFFSET(3)] -
  APPROX_QUANTILES(num_distinct_cardiac, 4)[OFFSET(1)] AS iqr_distinct_cardiac_procedures
FROM counts;