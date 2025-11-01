WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),
eligible_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
),
mcs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(long_title) LIKE '%extracorporeal membrane oxygenation%'
     OR LOWER(long_title) LIKE '%ventricular assist%'
     OR LOWER(long_title) LIKE '%cardiac assist%'
     OR LOWER(long_title) LIKE '%heart assist%'
     OR LOWER(long_title) LIKE '%ecmo%'
),
mcs_procs AS (
  SELECT DISTINCT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN mcs_codes m 
    ON p.icd_code = m.icd_code 
    AND p.icd_version = m.icd_version
  INNER JOIN eligible_admissions ea 
    ON p.hadm_id = ea.hadm_id
),
counts_per_hadm AS (
  SELECT 
    ea.hadm_id,
    COALESCE(mcs_count.num_distinct, 0) AS num_distinct_mcs
  FROM eligible_admissions ea
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_distinct
    FROM mcs_procs
    GROUP BY hadm_id
  ) mcs_count ON ea.hadm_id = mcs_count.hadm_id
)
SELECT 
  PERCENTILE_CONT(num_distinct_mcs, 0.25) OVER() AS q1,
  PERCENTILE_CONT(num_distinct_mcs, 0.75) OVER() AS q3,
  PERCENTILE_CONT(num_distinct_mcs, 0.75) OVER() - PERCENTILE_CONT(num_distinct_mcs, 0.25) OVER() AS iqr
FROM counts_per_hadm;