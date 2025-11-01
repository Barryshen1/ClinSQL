WITH female_84_94 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 84 AND 94
),
echo_procedures AS (
  SELECT h.hadm_id, h.hcpcs_cd
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN female_84_94 f ON h.subject_id = f.subject_id
  WHERE h.hcpcs_cd LIKE '933%' OR h.hcpcs_cd LIKE '934%'
),
echo_count_per_admission AS (
  SELECT hadm_id, COUNT(DISTINCT hcpcs_cd) AS distinct_echo_count
  FROM echo_procedures
  GROUP BY hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_echo_count, 0.25) OVER() AS percentile_25
FROM echo_count_per_admission
LIMIT 1;