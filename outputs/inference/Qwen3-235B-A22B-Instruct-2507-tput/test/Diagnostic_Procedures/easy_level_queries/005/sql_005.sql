WITH echo_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(long_description) LIKE '%echocardiography%'
     OR LOWER(short_description) LIKE '%echocardiography%'
     OR LOWER(long_description) LIKE '%echo%'
     OR LOWER(short_description) LIKE '%echo%'
),
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
patient_echo_counts AS (
  SELECT
    pf.subject_id,
    COUNT(hc.chartdate) AS echo_count
  FROM patients_filtered pf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    ON pf.subject_id = hc.subject_id
  INNER JOIN echo_codes ec
    ON hc.hcpcs_cd = ec.code
  GROUP BY pf.subject_id
)
SELECT
  APPROX_QUANTILES(echo_count, 1000)[OFFSET(750)] AS p75_echo_procedures
FROM patient_echo_counts;