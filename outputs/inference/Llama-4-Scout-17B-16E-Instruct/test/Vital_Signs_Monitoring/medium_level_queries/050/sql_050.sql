WITH 
  -- Calculate average HR per stay for ICU patients aged 67-77
  hr_events AS (
    SELECT 
      ic.stay_id,
      ce.charttime,
      ce.valuenum AS hr
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON 
      ce.subject_id = ic.subject_id AND ce.hadm_id = ic.hadm_id
    WHERE 
      ce.itemid = 220050  -- Heart Rate
      AND ic.intime BETWEEN TIMESTAMP_SUB(ic.intime, INTERVAL  24 HOUR) AND ic.intime
      AND ic.first_careunit = ic.last_careunit  -- Ensure it's the first ICU stay
  ),
  
  avg_hr_per_stay AS (
    SELECT 
      stay_id,
      AVG(hr) AS avg_hr
    FROM 
      hr_events
    GROUP BY 
      stay_id
  ),
  
  -- Patients' demographics
  patients_info AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.gender,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  
  -- Link patients with their ICU stays
  icu_patients AS (
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      pi.gender,
      pi.anchor_age,
      ic.stay_id
    FROM 
      patients_info pi
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON 
      pi.hadm_id = ic.hadm_id AND pi.subject_id = ic.subject_id
    WHERE 
      pi.anchor_age BETWEEN 67 AND 77 AND pi.gender = 'F'
  ),
  
  ranked_hr AS (
    SELECT 
      ahps.stay_id,
      ahps.avg_hr,
      PERCENT_RANK() OVER (ORDER BY ahps.avg_hr) AS percentile
    FROM 
      avg_hr_per_stay ahps
    JOIN 
      icu_patients ip
    ON 
      ahps.stay_id = ip.stay_id
  )

SELECT 
  percentile
FROM 
  ranked_hr
WHERE 
  avg_hr = 110;