WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
echo_procs AS (
  SELECT h.subject_id, h.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%echocardiography%'
     OR LOWER(d.long_description) LIKE '%echocardiography%'
     OR LOWER(d.short_description) LIKE '%echo%'
     OR LOWER(d.long_description) LIKE '%echo%'
),
patient_echo_counts AS (
  SELECT
    e.subject_id,
    COUNT(ep.chartdate) AS echo_count
  FROM eligible_patients e
  LEFT JOIN echo_procs ep
    ON e.subject_id = ep.subject_id
  GROUP BY e.subject_id
)
SELECT
  PERCENTILE_CONT(echo_count, 0.25) OVER() AS percentile_25
FROM patient_echo_counts
LIMIT 1;