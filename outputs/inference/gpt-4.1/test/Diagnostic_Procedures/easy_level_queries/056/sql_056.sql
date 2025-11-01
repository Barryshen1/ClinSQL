WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
mcs_codes AS (
  SELECT '37.61' AS icd_code, 9 AS icd_version UNION ALL -- IABP
  SELECT '5A02210', 10 UNION ALL -- IABP
  SELECT '37.66', 9 UNION ALL -- VAD
  SELECT '02HA0QZ', 10 UNION ALL -- VAD
  SELECT '02HA0RZ', 10 UNION ALL -- VAD
  SELECT '02HA0SZ', 10 UNION ALL -- VAD
  SELECT '02HA0TZ', 10 UNION ALL -- VAD
  SELECT '39.65', 9 UNION ALL -- ECMO
  SELECT '5A15223', 10 UNION ALL -- ECMO
  SELECT '5A15224', 10 UNION ALL -- ECMO
  SELECT '5A1522F', 10 UNION ALL -- ECMO
  SELECT '5A1522G', 10 UNION ALL -- ECMO
  SELECT '5A1522H', 10 -- ECMO
),
mcs_procs AS (
  SELECT DISTINCT p.subject_id, pr.icd_code
  FROM cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN mcs_codes mc
    ON pr.icd_code = mc.icd_code AND pr.icd_version = mc.icd_version
),
mcs_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT mp.icd_code) AS num_mcs_procs
  FROM cohort c
  LEFT JOIN mcs_procs mp
    ON c.subject_id = mp.subject_id
  GROUP BY c.subject_id
)
SELECT
  PERCENTILE_CONT(num_mcs_procs, 0.25) OVER() AS mcs_proc_25th_percentile
FROM mcs_counts;