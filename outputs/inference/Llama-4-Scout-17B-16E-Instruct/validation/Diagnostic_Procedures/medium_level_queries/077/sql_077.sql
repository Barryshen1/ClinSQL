WITH 
  -- Identify septic shock patients
  septic_shock_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 57 AND 67
      AND (d.icd_code LIKE '785.52'  -- Septic shock ICD-9 code
           OR d.icd_code LIKE 'R65.21')  -- Septic shock ICD-10 code
  ),

  -- Identify ICU stays
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      outtime,
      TIMESTAMP_DIFF(outtime, intime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Identify ultrasound and echo events
  ultrasound_events AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      COUNT(ce.itemid) AS ultrasound_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON ce.itemid = di.itemid
    WHERE 
      LOWER(di.label) LIKE '%ultrasound%' 
      OR LOWER(di.label) LIKE '%echo%'
    GROUP BY 
      ce.subject_id, 
      ce.hadm_id
  )

-- Join and calculate percentiles
SELECT 
  CASE 
    WHEN iss.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN iss.los BETWEEN 4 AND 7 THEN '4-7'
    ELSE 'Outside range'
  END AS los_group,
  CASE 
    WHEN iss.stay_id IS NOT NULL THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_group,
  APPROX_QUANTILES(ue.ultrasound_count, 0.25)[OFFSET(0)] AS p25,
  APPROX_QUANTILES(ue.ultrasound_count, 0.5)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(ue.ultrasound_count, 0.75)[OFFSET(0)] AS p75
FROM 
  septic_shock_patients ssp
  LEFT JOIN icu_stays iss 
    ON ssp.subject_id = iss.subject_id AND ssp.hadm_id = iss.hadm_id
  LEFT JOIN ultrasound_events ue 
    ON ssp.subject_id = ue.subject_id AND ssp.hadm_id = ue.hadm_id
GROUP BY 
  los_group, 
  icu_group;