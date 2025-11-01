WITH 
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  spo2_events AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      charttime, 
      valuenum AS spo2
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid = 220050
  ),
  
  stay_spo2_averages AS (
    SELECT 
      stay_id, 
      AVG(spo2) AS avg_spo2
    FROM 
      spo2_events
    GROUP BY 
      stay_id
  ),
  
  patient_info AS (
    SELECT 
      subject_id, 
      gender, 
      anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients`
  ),
  
  filtered_stays AS (
    SELECT 
      s.stay_id, 
      s.avg_spo2
    FROM 
      stay_spo2_averages s
    JOIN 
      icu_stays i ON s.stay_id = i.stay_id
    JOIN 
      patient_info p ON i.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 87 AND 97
  )

SELECT 
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(88)] AS percentile_88
FROM 
  filtered_stays;