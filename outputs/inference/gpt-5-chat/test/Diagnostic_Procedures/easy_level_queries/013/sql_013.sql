WITH valve_procs AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_valve_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
   AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND LOWER(dpr.long_title) LIKE '%valve%'
    AND (
         LOWER(dpr.long_title) LIKE '%repair%' 
      OR LOWER(dpr.long_title) LIKE '%replacement%'
    )
  GROUP BY p.subject_id, pr.hadm_id
)
SELECT
  MIN(distinct_valve_proc_count) AS min_distinct_valve_proc_per_admission
FROM valve_procs;