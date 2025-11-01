WITH surgeries AS (
  SELECT 
    hadm_id, 
    MIN(chartdate) AS first_surgery_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,  -- Removed redundant TIMESTAMP cast (native type)
    i.outtime,  -- Removed redundant TIMESTAMP cast
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN surgeries s
    ON a.hadm_id = s.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
    AND i.intime >= TIMESTAMP(s.first_surgery_date)  -- Direct TIMESTAMP comparison
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.hadm_id 
    ORDER BY i.intime  -- Use native column
  ) = 1
),
medications AS (
  -- IV Medications
  SELECT 
    c.stay_id,
    di.label AS medication_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE 
    ie.starttime >= c.intime
    AND ie.starttime < 
      LEAST(
        TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR),
        COALESCE(c.outtime, TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR))
      )
  
  UNION DISTINCT
  
  -- Non-IV Medications (EMAR) - Fix: Convert charttime to TIMESTAMP
  SELECT 
    c.stay_id,
    e.medication AS medication_name
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id 
    AND c.subject_id = e.subject_id
  WHERE 
    TIMESTAMP(e.charttime) >= c.intime  -- Convert to TIMESTAMP
    AND TIMESTAMP(e.charttime) <  -- Convert to TIMESTAMP
      LEAST(
        TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR),
        COALESCE(c.outtime, TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR))
      )
),
med_complexity AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT medication_name) AS complexity
  FROM medications
  GROUP BY stay_id
),
readmissions AS (
  SELECT 
    a1.hadm_id,
    SIGN(COUNT(a2.hadm_id)) AS readmit_30day
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)  -- Fixed: TIMESTAMP_ADD
  GROUP BY a1.hadm_id
),
cohort_outcomes AS (
  SELECT 
    c.*,
    COALESCE(mc.complexity, 0) AS complexity,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_hospital,  -- Fixed: TIMESTAMP_DIFF
    c.hospital_expire_flag AS mortality,
    COALESCE(r.readmit_30day, 0) AS readmit_30day
  FROM cohort c
  LEFT JOIN med_complexity mc
    ON c.stay_id = mc.stay_id
  LEFT JOIN readmissions r
    ON c.hadm_id = r.hadm_id
),
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY complexity) AS quintile
  FROM cohort_outcomes
)
SELECT 
  quintile,
  COUNT(*) AS num_patients,
  AVG(los_hospital) AS avg_los,
  AVG(mortality) * 100 AS mortality_rate_pct,
  AVG(readmit_30day) * 100 AS readmit_30day_rate_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;