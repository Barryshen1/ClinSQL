WITH 
  -- Identify heart failure hospitalizations in males
  heart_failure_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON 
      d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
      dd.long_title LIKE '%Heart failure%' 
      AND p.gender = 'M'
      AND p.anchor_age = 65
  ),

  -- Find earliest charttime for serum sodium for each admission
  earliest_sodium_charttime AS (
    SELECT 
      hadm_id,
      MIN(charttime) AS earliest_charttime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid = 50808
    GROUP BY 
      hadm_id
  ),

  -- Find admission serum sodium for heart failure hospitalizations
  admission_sodium AS (
    SELECT 
      hfa.hadm_id,
      le.valuenum AS sodium_level
    FROM 
      heart_failure_admissions hfa
    JOIN 
      earliest_sodium_charttime esct
    ON 
      hfa.hadm_id = esct.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON 
      hfa.hadm_id = le.hadm_id
      AND esct.earliest_charttime = le.charttime
      AND le.itemid = 50808
  )

-- Find the minimum admission serum sodium across all heart failure hospitalizations
SELECT 
  MIN(sodium_level) AS min_admission_sodium
FROM 
  admission_sodium;