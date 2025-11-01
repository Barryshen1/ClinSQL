WITH 
patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
),
general_ward_stays AS (
  SELECT 
    hadm_id,
    COUNTIF(careunit = 'Ward') > 0 AS was_on_general_ward
  FROM 
    `physionet-data.mimiciv_3_1_hosp.transfers`
  GROUP BY 
    hadm_id
),
los_discharge_status AS (
  SELECT 
    pa.hadm_id,
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los,
    CASE
      WHEN pa.discharge_location = 'HOME' THEN 'home'
      WHEN pa.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN pa.deathtime IS NOT NULL THEN 'death'
      ELSE 'other'
    END AS discharge_status
  FROM 
    patient_admissions pa
  INNER JOIN 
    general_ward_stays gws ON pa.hadm_id = gws.hadm_id
  WHERE 
    gws.was_on_general_ward
)
SELECT 
  discharge_status,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_7day
FROM 
  los_discharge_status
WHERE 
  discharge_status IN ('home', 'hospice', 'death')
GROUP BY 
  discharge_status;