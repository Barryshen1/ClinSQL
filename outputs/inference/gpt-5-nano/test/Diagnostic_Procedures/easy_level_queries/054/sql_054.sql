WITH eligible AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- Echocardiography-related HCPCS events per hospitalization
echo_events AS (
  SELECT ce.subject_id, ce.hadm_id,
         COUNT(DISTINCT ce.hcpcs_cd) AS distinct_echo_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ce.hadm_id = a.hadm_id
  JOIN eligible AS e
    ON ce.subject_id = e.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d
    ON ce.hcpcs_cd = d.code
  WHERE LOWER(d.long_description) LIKE '%echocardiography%'
     OR LOWER(d.long_description) LIKE '%echo%'
  GROUP BY ce.subject_id, ce.hadm_id
),

-- Per-patient maximum across hospitalizations
max_by_subject AS (
  SELECT subject_id,
         MAX(distinct_echo_count) AS max_distinct_echoes_per_hadm
  FROM echo_events
  GROUP BY subject_id
)

SELECT subject_id,
       max_distinct_echoes_per_hadm
FROM max_by_subject
ORDER BY subject_id;