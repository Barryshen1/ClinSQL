WITH rrt_patients AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data`.mimiciv_3_1_icu.icustays i
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data`.mimiciv_3_1_icu.procedureevents pe
    ON i.stay_id = pe.stay_id
  INNER JOIN `physionet-data`.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) IN (
    'dialysis', 'crrt', 'hemodialysis', 'renal replacement therapy',
    'renal replacement', 'rrt', 'continuous renal replacement therapy'
  )
),

vital_events AS (
  SELECT
    rrt.stay_id,
    rrt.intime,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    di.label AS vital_sign
  FROM rrt_patients rrt
  INNER JOIN `physionet-data`.mimiciv_3_1_icu.chartevents ce
    ON rrt.stay_id = ce.stay_id
  INNER JOIN `physionet-data`.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= rrt.intime
    AND ce.charttime <= DATETIME_ADD(rrt.intime, INTERVAL 72 HOUR)
    AND di.label IN ('MAP', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),

hourly_vitals AS (
  SELECT
    stay_id,
    DATETIME_TRUNC(charttime, HOUR) AS hour_bin,
    MAX(CASE WHEN vital_sign = 'MAP' THEN valuenum END) AS map_val,
    MAX(CASE WHEN vital_sign = 'Heart Rate' THEN valuenum END) AS hr_val
  FROM vital_events
  GROUP BY stay_id, DATETIME_TRUNC(charttime, HOUR)
),

vital_instability AS (
  SELECT
    stay_id,
    SUM(CASE WHEN map_val < 65 AND hr_val > 100 THEN 1 ELSE 0 END) AS vii_hours
  FROM hourly_vitals
  GROUP BY stay_id
),

grouped_stats AS (
  SELECT
    CASE 
      WHEN rp.gender = 'F' AND rp.anchor_age BETWEEN 58 AND 68 THEN 'Target (F, 58-68)'
      ELSE 'Other RRT'
    END AS group_label,
    vi.vii_hours,
    rp.los,
    rp.hospital_expire_flag
  FROM rrt_patients rp
  INNER JOIN vital_instability vi
    ON rp.stay_id = vi.stay_id
)

SELECT
  group_label,
  PERCENTILE_CONT(vii_hours, 0.25) AS vii_25th,
  PERCENTILE_CONT(vii_hours, 0.50) AS vii_50th,
  PERCENTILE_CONT(vii_hours, 0.75) AS vii_75th,
  PERCENTILE_CONT(vii_hours, 0.90) AS vii_90th,
  PERCENTILE_CONT(vii_hours, 0.75) - PERCENTILE_CONT(vii_hours, 0.25) AS vii_iqr,
  AVG(los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM grouped_stats
GROUP BY group_label
ORDER BY group_label;