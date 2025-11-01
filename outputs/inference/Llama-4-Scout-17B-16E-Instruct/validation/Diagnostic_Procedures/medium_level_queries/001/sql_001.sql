WITH 
  -- Identify ACS patients
  acs_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 77 AND 87
      AND p.gender = 'F'
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '410%'  -- ACS ICD code
      )
  ),

  -- Categorize LOS and diagnosis type
  acs_stays AS (
    SELECT 
      ap.subject_id,
      ap.hadm_id,
      ap.anchor_age,
      ap.los,
      CASE 
        WHEN ap.los BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN ap.los BETWEEN 5 AND 8 THEN '5-8 days'
        ELSE 'Outside range'
      END AS los_category,
      CASE 
        WHEN d.seq_num = 1 THEN 'Primary'
        ELSE 'Secondary'
      END AS diagnosis_type
    FROM 
      acs_patients ap
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      ap.hadm_id = d.hadm_id
  ),

  -- Count radiography/CT procedures
  radiography_ct_counts AS (
    SELECT 
      hadm_id,
      COUNT(*) AS radiography_ct_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_code LIKE '87%'  -- Radiography/CT ICD code
    GROUP BY 
      hadm_id
  )

-- Calculate mean, min, max radiography/CT counts
SELECT 
  asy.los_category,
  asy.diagnosis_type,
  AVG(rcc.radiography_ct_count) AS mean_count,
  MIN(rcc.radiography_ct_count) AS min_count,
  MAX(rcc.radiography_ct_count) AS max_count
FROM 
  acs_stays asy
LEFT JOIN 
  radiography_ct_counts rcc
ON 
  asy.hadm_id = rcc.hadm_id
GROUP BY 
  asy.los_category,
  asy.diagnosis_type;