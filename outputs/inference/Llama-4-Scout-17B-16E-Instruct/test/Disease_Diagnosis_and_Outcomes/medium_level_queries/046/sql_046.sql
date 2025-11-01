WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 72 AND 82
      AND a.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.9')  -- Heart Failure ICD-9 codes
          OR icd_code IN ('I11.0', 'I13.0', 'I13.2', 'I50.1', 'I50.2', 'I50.9')  -- Heart Failure ICD-10 codes
      )
  ),

  -- Identify ICU stays for patients of interest
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
    WHERE 
      hadm_id IN (SELECT hadm_id FROM patients_of_interest)
  ),

  -- Categorize LOS for ICU and non-ICU stays
  los_categories AS (
    SELECT 
      'ICU' AS care_type,
      hadm_id,
      CASE 
        WHEN los <= 3 THEN '≤3 days'
        WHEN los BETWEEN 4 AND 6 THEN '4–6 days'
        WHEN los BETWEEN 7 AND 10 THEN '7–10 days'
        ELSE '>10 days'
      END AS los_category
    FROM 
      icu_stays
    UNION ALL
    SELECT 
      'Non-ICU' AS care_type,
      hadm_id,
      CASE 
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 3 THEN '≤3 days'
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 6 THEN '4–6 days'
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 7 AND 10 THEN '7–10 days'
        ELSE '>10 days'
      END AS los_category
    FROM 
      patients_of_interest
    WHERE 
      hadm_id NOT IN (SELECT hadm_id FROM icu_stays)
  ),

  -- Calculate in-hospital mortality and comorbidity count
  outcomes AS (
    SELECT 
      hadm_id,
      hospital_expire_flag,
      COALESCE(drg_count, 0) AS comorbidity_count
    FROM 
      patients_of_interest
    LEFT JOIN 
      (
        SELECT 
          subject_id,
          hadm_id,
          COUNT(DISTINCT drg_code) AS drg_count
        FROM 
          `physionet-data.mimiciv_3_1_hosp.drgcodes`
        GROUP BY 
          subject_id, hadm_id
      ) 
    USING (hadm_id)
  )

-- Final analysis
SELECT 
  lc.los_category,
  lc.care_type,
  COUNT(DISTINCT o.hadm_id) AS num_patients,
  SUM(CASE WHEN o.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT o.hadm_id) AS in_hospital_mortality_rate,
  APPROX_QUANTILES(o.comorbidity_count, 1000)[500] AS median_comorbidity_count
FROM 
  los_categories lc
JOIN 
  outcomes o
ON 
  lc.hadm_id = o.hadm_id
GROUP BY 
  lc.los_category, lc.care_type
ORDER BY 
  lc.los_category, lc.care_type;