WITH 
  -- Identify male patients aged 39-49 with ACS and LOS 1-7 days
  eligible_patients AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender,
      CASE 
        WHEN di.icd_code LIKE '410%' THEN 'ACS'
        ELSE 'Non-ACS'
      END AS diagnosis_type,
      CASE 
        WHEN a.admission_type = 'Primary' THEN 'Primary'
        ELSE 'Secondary'
      END AS admission_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.hadm_id = di.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 39 AND 49
      AND di.icd_code LIKE '410%'  -- ACS ICD code
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  ),
  
  -- Count ultrasounds (including echo) per admission
  ultrasounds AS (
    SELECT 
      hadm_id,
      COUNT(DISTINCT itemid) AS ultrasound_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE label LIKE '%ultrasound%' OR label LIKE '%echo%'
      )
    GROUP BY 
      hadm_id
  ),
  
  -- Stratify by LOS and ACS type
  results AS (
    SELECT 
      ep.hadm_id,
      ep.diagnosis_type,
      ep.admission_type,
      CASE 
        WHEN TIMESTAMP_DIFF(ep.dischtime, ep.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN TIMESTAMP_DIFF(ep.dischtime, ep.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      END AS los_category,
      u.ultrasound_count
    FROM 
      eligible_patients ep
    LEFT JOIN 
      ultrasounds u ON ep.hadm_id = u.hadm_id
  )

-- Calculate percentiles
SELECT 
  los_category,
  diagnosis_type,
  admission_type,
  APPROX_QUANTILES(ultrasound_count, 0.25)[OFFSET(0)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 0.5)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 0.75)[OFFSET(0)] AS p75
FROM 
  results
GROUP BY 
  los_category, 
  diagnosis_type,
  admission_type
ORDER BY 
  los_category, 
  diagnosis_type,
  admission_type;