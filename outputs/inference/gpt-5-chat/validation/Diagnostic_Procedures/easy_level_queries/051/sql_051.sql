WITH male_41_51 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),
ecg_proc AS (
  SELECT p.subject_id, pr.icd_code, pr.icd_version
  FROM male_41_51 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ecg%'
     OR LOWER(dp.long_title) LIKE '%ekg%'
     OR LOWER(dp.long_title) LIKE '%electrocardiogram%'
     OR LOWER(dp.long_title) LIKE '%electrocardiographic%'
     OR LOWER(dp.long_title) LIKE '%electrocardiography%'
     OR LOWER(dp.long_title) LIKE '%cardiac monitoring%'
     OR LOWER(dp.long_title) LIKE '%telemetry%'
),
distinct_counts AS (
  SELECT subject_id,
         COUNT(DISTINCT icd_code) AS distinct_ecg_proc_count
  FROM ecg_proc
  GROUP BY subject_id
)
SELECT PERCENTILE_CONT(distinct_ecg_proc_count, 0.75) OVER() AS p75_distinct_ecg_procs
FROM distinct_counts
LIMIT 1;