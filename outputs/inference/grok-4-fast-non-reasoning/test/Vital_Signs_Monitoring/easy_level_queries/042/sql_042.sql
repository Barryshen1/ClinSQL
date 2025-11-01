WITH rr_measurements AS (
  -- Get all respiratory rate measurements for ICU stays
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS rr
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.stay_id IS NOT NULL  -- Ensure ICU context
),
patient_max_rr AS (
  -- Compute max RR per patient (across all their ICU stays)
  SELECT 
    subject_id,
    MAX(rr) AS max_rr
  FROM 
    rr_measurements
  GROUP BY 
    subject_id
  HAVING 
    max_rr IS NOT NULL
)
-- Compute SD of max RR for qualifying female patients aged 63-73
SELECT 
  STDDEV(max_rr) AS sd_max_respiratory_rate
FROM 
  patient_max_rr pmr
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON 
  pmr.subject_id = p.subject_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73;