WITH cohort AS (
  -- Select qualifying admissions with both diabetes AND heart failure diagnoses
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    ic.stay_id,
    CAST(ic.intime AS TIMESTAMP) AS stay_start,
    CAST(ic.outtime AS TIMESTAMP) AS stay_end,
    ic.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON a.hadm_id = ic.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_type != 'OBSERVATION'
    AND a.deathtime IS NULL
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
        AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR 
             d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR 
             d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%')
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
        AND d.icd_code LIKE 'I50%'
    )
    AND ic.los >= 72.0  -- Ensure valid final 72h window (fixed type: FLOAT64)
),

total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM cohort
),

glp_initiations AS (
  -- GLP-1 administrations by window (using starttime for initiation)
  SELECT 
    c.hadm_id,
    CASE 
      WHEN CAST(ie.starttime AS TIMESTAMP) BETWEEN c.stay_start AND TIMESTAMP_ADD(c.stay_start, INTERVAL 72 HOUR) 
      THEN 'first_72h'
      WHEN CAST(ie.starttime AS TIMESTAMP) BETWEEN TIMESTAMP_SUB(c.stay_end, INTERVAL 72 HOUR) AND c.stay_end 
      THEN 'final_72h'
      ELSE NULL
    END AS time_window
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON c.stay_id = ie.stay_id
  WHERE ie.itemid IN (225798, 225487, 228527)  -- Injectable GLP-1s: semaglutide, liraglutide, dulaglutide
    AND ie.ordercategoryname = 'Single'  -- Focus on direct administrations/infusions
    AND (ie.statusdescription != 'Rewritten' OR ie.statusdescription IS NULL)
    AND ie.amount > 0  -- Valid positive dose
  GROUP BY c.hadm_id, time_window  -- Dedup multiple administrations per window per admission
  HAVING time_window IS NOT NULL
),

window_summary AS (
  SELECT 
    w.time_window,
    COUNT(DISTINCT gi.hadm_id) AS initiations
  FROM (
    SELECT 'first_72h' AS time_window
    UNION ALL
    SELECT 'final_72h' AS time_window
  ) w
  LEFT JOIN glp_initiations gi
    ON w.time_window = gi.time_window
  GROUP BY w.time_window
)

-- Final metrics
SELECT 
  time_window,
  initiations,
  ROUND(SAFE_DIVIDE(initiations, t.total) * 100, 2) AS initiation_rate_percent
FROM window_summary
CROSS JOIN total_admissions t

UNION ALL

SELECT 
  'absolute_change' AS time_window,
  NULL AS initiations,
  ROUND(
    SAFE_DIVIDE(
      MAX(CASE WHEN ws.time_window = 'final_72h' THEN ws.initiations END), t.total
    ) * 100 -
    SAFE_DIVIDE(
      MAX(CASE WHEN ws.time_window = 'first_72h' THEN ws.initiations END), t.total
    ) * 100, 2
  ) AS initiation_rate_percent
FROM window_summary ws
CROSS JOIN total_admissions t

UNION ALL

SELECT 
  'relative_change_percent' AS time_window,
  NULL AS initiations,
  ROUND(
    SAFE_DIVIDE(
      (SAFE_DIVIDE(MAX(CASE WHEN ws.time_window = 'final_72h' THEN ws.initiations END), t.total) * 100 -
       SAFE_DIVIDE(MAX(CASE WHEN ws.time_window = 'first_72h' THEN ws.initiations END), t.total) * 100),
      SAFE_DIVIDE(MAX(CASE WHEN ws.time_window = 'first_72h' THEN ws.initiations END), t.total) * 100
    ) * 100, 2
  ) AS initiation_rate_percent
FROM window_summary ws
CROSS JOIN total_admissions t

ORDER BY 
  CASE time_window 
    WHEN 'first_72h' THEN 1 
    WHEN 'final_72h' THEN 2 
    WHEN 'absolute_change' THEN 3 
    ELSE 4 
  END;