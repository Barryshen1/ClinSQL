WITH female_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),
cardiac_procs AS (
  SELECT p.subject_id, pr.hadm_id, pr.icd_code, pr.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN female_cohort p
    ON pr.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%cardiac%'
     OR LOWER(dpr.long_title) LIKE '%heart%'
),
proc_counts AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS distinct_card_procs
  FROM cardiac_procs
  GROUP BY hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_card_procs, 0.25) OVER () AS p25_distinct_card_procs
FROM proc_counts
LIMIT 1;