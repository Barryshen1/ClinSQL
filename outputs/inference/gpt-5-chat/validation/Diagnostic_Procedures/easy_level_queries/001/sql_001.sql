WITH cardiac_proc_counts AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_cardiac_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(dpr.long_title) LIKE '%cardiac%'
  GROUP BY p.subject_id, pr.hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_cardiac_proc_count, 0.75) OVER () AS percentile_75_distinct_cardiac_procs
FROM cardiac_proc_counts
LIMIT 1;