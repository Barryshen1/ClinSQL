WITH 
  -- Identify heart failure patients
  heart_failure_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      CASE 
        WHEN d.icd_code IN ('428', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9') THEN 1 
        ELSE 0 
      END AS has_heart_failure
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 38 AND 48 AND
      d.icd_version = 9  -- Assuming ICD-9 for simplicity
  ),
  
  -- Identify ICU patients
  icu_patients AS (
    SELECT 
      hadm_id,
      1 AS in_icu
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Calculate Charlson Comorbidity Index (simplified)
  charlson_index AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT CASE WHEN icd_code IN ('401', '402', '403', '404', '405') THEN icd_code END) AS charlson_score
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),
  
  -- Hospital mortality
  hospital_mortality AS (
    SELECT 
      hadm_id,
      hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  
  -- LOS calculation
  admissions_with_los AS (
    SELECT 
      hadm_id,
      TIMESTAMPDIFF(DAY, admittime, dischtime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )

SELECT 
  COALESCE(icu.in_icu, 0) AS in_icu,
  -- LOS categories
  CASE 
    WHEN awl.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN awl.los BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  -- Charlson categories
  CASE 
    WHEN ci.charlson_score <= 3 THEN '<=3'
    WHEN ci.charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_category,
  -- Mortality rate
  AVG(CASE WHEN hm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  -- Mean comorbidity count
  AVG(ci.charlson_score) AS mean_comorbidity_count
FROM 
  heart_failure_patients hfp
  LEFT JOIN icu_patients icu ON hfp.hadm_id = icu.hadm_id
  JOIN admissions_with_los awl ON hfp.hadm_id = awl.hadm_id
  LEFT JOIN charlson_index ci ON hfp.subject_id = ci.subject_id AND hfp.hadm_id = ci.hadm_id
  JOIN hospital_mortality hm ON hfp.hadm_id = hm.hadm_id
WHERE 
  hfp.has_heart_failure = 1
GROUP BY 
  in_icu, los_category, charlson_category;