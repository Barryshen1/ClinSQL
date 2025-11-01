WITH qualifying_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 81
    AND p.anchor_age <= 91
),
distinct_counts AS (
  SELECT 
    qa.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN LOWER(dip.long_title) LIKE '%ecg%' 
        OR LOWER(dip.long_title) LIKE '%ekg%' 
        OR LOWER(dip.long_title) LIKE '%electrocardiogram%' 
        OR LOWER(dip.long_title) LIKE '%telemetry%' 
        OR LOWER(dip.long_title) LIKE '%cardiac monitoring%' 
      THEN pi.icd_code 
    END) AS num_distinct
  FROM qualifying_admissions qa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON qa.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  GROUP BY qa.hadm_id
)
SELECT STDDEV(num_distinct) AS standard_deviation
FROM distinct_counts;