WITH eligible_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
mcs_procedures AS (
  SELECT DISTINCT p.subject_id, p.icd_code
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(d.long_title) LIKE '%ecmo%'
     OR LOWER(d.long_title) LIKE '%lvad%'
     OR LOWER(d.long_title) LIKE '%rvad%'
     OR LOWER(d.long_title) LIKE '%bivad%'
     OR LOWER(d.long_title) LIKE '%total artificial heart%'
     OR LOWER(d.long_title) LIKE '%mechanical circulatory support%'
),
patient_mcs_counts AS (
  SELECT ep.subject_id,
         COUNT(DISTINCT mp.icd_code) AS num_distinct_mcs_procedures
  FROM eligible_patients ep
  LEFT JOIN mcs_procedures mp ON ep.subject_id = mp.subject_id
  GROUP BY ep.subject_id
)
SELECT PERCENTILE_CONT(num_distinct_mcs_procedures, 0.25) OVER () AS twenty_fifth_percentile
FROM patient_mcs_counts
LIMIT 1;