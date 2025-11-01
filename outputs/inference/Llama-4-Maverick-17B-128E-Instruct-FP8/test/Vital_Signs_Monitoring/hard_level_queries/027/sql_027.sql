WITH 
-- Step 1: Identify patients who are female, aged 58-68, and had RRT
rr_patients AS (
  SELECT DISTINCT p.subject_id, ic.stay_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON p.subject_id = ic.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ic.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND di.label LIKE '%Renal Replacement Therapy%'
),

-- Step 2: Extract relevant vital signs (MAP, HR) for these patients within the first 72 hours of ICU stay
vital_signs AS (
  SELECT rr.subject_id, rr.stay_id, ce.charttime, 
         MAX(CASE WHEN di.label = 'Mean Arterial Pressure' THEN ce.valuenum END) AS map,
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS hr
  FROM rr_patients rr
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON rr.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN rr.intime AND TIMESTAMP_ADD(rr.intime, INTERVAL 72 HOUR)
    AND di.label IN ('Mean Arterial Pressure', 'Heart Rate')
  GROUP BY rr.subject_id, rr.stay_id, ce.charttime
),

-- Step 3: Calculate vital-instability index and hypotensive/tachycardic hours
vital_instability AS (
  SELECT stay_id, 
         COUNTIF(map < 65 AND hr > 100) AS vital_instability_count,
         COUNT(*) AS total_count,
         SUM(CASE WHEN map < 65 OR hr > 100 THEN 1 ELSE 0 END) AS hypotensive_tachycardic_hours
  FROM vital_signs
  GROUP BY stay_id
),

-- Step 4: Calculate ICU LOS and mortality
icu_outcomes AS (
  SELECT ic.stay_id, 
         TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR) AS icu_los_hours,
         CASE WHEN ic.outtime = p.dod THEN 1 ELSE 0 END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ic.subject_id = p.subject_id
)

-- Final query to report required statistics
SELECT 
  APPROX_QUANTILES(vi.vital_instability_count / vi.total_count, 100)[OFFSET(25)] AS vital_instability_25th,
  APPROX_QUANTILES(vi.vital_instability_count / vi.total_count, 100)[OFFSET(50)] AS vital_instability_median,
  APPROX_QUANTILES(vi.vital_instability_count / vi.total_count, 100)[OFFSET(75)] AS vital_instability_75th,
  APPROX_QUANTILES(vi.vital_instability_count / vi.total_count, 100)[OFFSET(90)] AS vital_instability_90th,
  AVG(vi.hypotensive_tachycardic_hours) AS avg_hypotensive_tachycardic_hours,
  AVG(io.icu_los_hours) AS avg_icu_los_hours,
  AVG(io.mortality) AS mortality_rate
FROM vital_instability vi
JOIN icu_outcomes io ON vi.stay_id = io.stay_id
JOIN rr_patients rr ON vi.stay_id = rr.stay_id;