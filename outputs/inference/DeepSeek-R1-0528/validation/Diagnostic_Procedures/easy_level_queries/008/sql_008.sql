WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
echo_events AS (
  SELECT DISTINCT subject_id, hadm_id, chartdate, code
  FROM (
    -- ICD procedures
    SELECT p.subject_id, p.hadm_id, p.chartdate, p.icd_code AS code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
      LOWER(d.long_title) LIKE '%echocardiogram%' 
      OR LOWER(d.long_title) LIKE '%echocardiography%'

    UNION ALL

    -- HCPCS events
    SELECT h.subject_id, h.hadm_id, h.chartdate, h.hcpcs_cd AS code
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
    WHERE 
      LOWER(d.short_description) LIKE '%echocardiogram%' 
      OR LOWER(d.short_description) LIKE '%echocardiography%'
      OR LOWER(d.long_description) LIKE '%echocardiogram%' 
      OR LOWER(d.long_description) LIKE '%echocardiography%'
  )
),
patient_echo_count AS (
  SELECT 
    cohort.subject_id,
    COUNT(echo_events.subject_id) AS echo_count
  FROM cohort
  LEFT JOIN echo_events
    ON cohort.subject_id = echo_events.subject_id
  GROUP BY cohort.subject_id
)
SELECT 
  APPROX_QUANTILES(echo_count, 4)[OFFSET(1)] AS percentile_25
FROM patient_echo_count;