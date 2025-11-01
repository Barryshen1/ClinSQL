WITH 
  -- Extract relevant patient data
  patient_data AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  ),

  -- Extract ICU stay data
  icu_stay_data AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Extract RR data
  rr_data AS (
    SELECT 
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS rr_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE 
      di.label = 'Respiratory Rate'
  ),

  -- Calculate per-stay average RR
  avg_rr_data AS (
    SELECT 
      rr.subject_id,
      rr.hadm_id,
      rr.stay_id,
      AVG(rr.rr_value) AS avg_rr
    FROM 
      rr_data rr
    JOIN 
      icu_stay_data isd
      ON rr.hadm_id = isd.hadm_id AND rr.stay_id = isd.stay_id
    WHERE 
      rr.charttime BETWEEN isd.intime AND TIMESTAMP_ADD(isd.intime, INTERVAL 48 HOUR)
    GROUP BY 
      rr.subject_id,
      rr.hadm_id,
      rr.stay_id
  ),

  -- Categorize average RR
  categorized_rr AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      CASE 
        WHEN avg_rr < 12 THEN '<12'
        WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
        WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
        ELSE '>=30'
      END AS avg_rr_category
    FROM 
      avg_rr_data
  ),

  -- Extract stroke data
  stroke_data AS (
    SELECT 
      subject_id,
      hadm_id,
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN (
        SELECT 
          icd_code 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE 
          long_title LIKE '%Stroke%' 
          OR long_title LIKE '%Cerebrovascular%'
      )
  ),

  -- Join and group data
  final_data AS (
    SELECT 
      p.anchor_age,
      p.gender,
      cr.avg_rr_category,
      COUNT(DISTINCT cr.stay_id) AS num_patients,
      SUM(CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS num_stroke
    FROM 
      patient_data p
    JOIN 
      categorized_rr cr
      ON p.subject_id = cr.subject_id AND p.hadm_id = cr.hadm_id
    LEFT JOIN 
      stroke_data sd
      ON p.subject_id = sd.subject_id AND p.hadm_id = sd.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 41 AND 51
    GROUP BY 
      p.anchor_age,
      p.gender,
      cr.avg_rr_category
  )

SELECT 
  anchor_age,
  gender,
  avg_rr_category,
  num_patients,
  num_stroke
FROM 
  final_data
ORDER BY 
  anchor_age,
  gender,
  avg_rr_category;