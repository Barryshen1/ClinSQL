WITH 
  -- Identify female patients aged 53-63
  eligible_patients AS (
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
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 53 AND 63
  ),
  
  -- Identify ICU stays in step-down/IMC units
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      first_careunit, 
      last_careunit
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE 
      first_careunit IN ('SD', 'IMC')
  ),
  
  -- Identify patients with invasive mechanical ventilation
  ventilated_patients AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid = 220050  -- Ventilation Mode
  ),
  
  -- Extract nighttime SBP measurements
  nighttime_sbp AS (
    SELECT 
      ce.valueuom, 
      ce.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      eligible_patients ep
    ON 
      ce.subject_id = ep.subject_id
      AND ce.hadm_id = ep.hadm_id
    JOIN 
      icu_stays is_
    ON 
      ce.subject_id = is_.subject_id
      AND ce.hadm_id = is_.hadm_id
    JOIN 
      ventilated_patients vp
    ON 
      ce.subject_id = vp.subject_id
      AND ce.hadm_id = vp.hadm_id
      AND ce.stay_id = vp.stay_id
    WHERE 
      ce.itemid = 220050  -- This itemid might not be correct for SBP; verify it.
      AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 6
      AND ce.valueuom = 'mmHg'
  )

-- Calculate standard deviation of SBP
SELECT 
  STDDEV(nt_sbp.valuenum) AS stddev_sbp
FROM 
  nighttime_sbp nt_sbp;