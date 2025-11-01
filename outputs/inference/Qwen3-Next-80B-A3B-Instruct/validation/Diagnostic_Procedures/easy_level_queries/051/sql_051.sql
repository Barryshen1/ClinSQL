WITH telemetry_episodes AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT c.stay_id) AS telemetry_stay_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    d.linksto = 'chartevents'
    AND (
      LOWER(d.label) LIKE '%ecg%'
      OR LOWER(d.label) LIKE '%telemetry%'
      OR LOWER(d.label) LIKE '%cardiac monitor%'
    )
  GROUP BY 
    c.subject_id
),
patient_procedures AS (
  SELECT 
    p.subject_id,
    COALESCE(t.telemetry_stay_count, 0) AS total_ecg_telemetry_procedures
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN 
    telemetry_episodes t ON p.subject_id = t.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
)
SELECT 
  PERCENTILE_CONT(total_ecg_telemetry_procedures, 0.75) AS p75_ecg_telemetry_procedures
FROM 
  patient_procedures;