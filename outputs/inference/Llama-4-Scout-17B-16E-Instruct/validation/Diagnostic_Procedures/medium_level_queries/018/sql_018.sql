WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 80 AND 90
  ),

  -- Identify relevant admissions and ICU stays
  admissions_stays AS (
    SELECT 
      a.hadm_id,
      ic.stay_id,
      ic.intime,
      ic.outtime,
      TIMESTAMP_DIFF(ic.outtime, ic.intime, 'DAY') AS stay_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    WHERE 
      a.subject_id IN (SELECT subject_id FROM patients_of_interest)
  ),

  -- Identify patients with hemorrhagic stroke
  hemorrhagic_stroke_admissions AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '430%'  -- ICD code for hemorrhagic stroke
  ),

  -- Identify ultrasound procedures
  ultrasounds AS (
    SELECT 
      hadm_id,
      COUNT(*) AS ultrasound_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE label LIKE '%Ultrasound%' 
        OR abbreviation LIKE '%Ultrasound%'
      )
    GROUP BY 
      hadm_id
  )

-- Calculate statistics for 1-4 vs 5-7 day stays
SELECT 
  CASE 
    WHEN stay_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN stay_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS stay_duration,
  AVG(IFNULL(ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(IFNULL(ultrasound_count, 0)) AS min_ultrasounds,
  MAX(IFNULL(ultrasound_count, 0)) AS max_ultrasounds
FROM 
  admissions_stays
  JOIN hemorrhagic_stroke_admissions hsa 
    ON admissions_stays.hadm_id = hsa.hadm_id
  LEFT JOIN ultrasounds 
    ON admissions_stays.hadm_id = ultrasounds.hadm_id
WHERE 
  stay_days BETWEEN 1 AND 7
GROUP BY 
  CASE 
    WHEN stay_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN stay_days BETWEEN 5 AND 7 THEN '5-7 days'
  END;