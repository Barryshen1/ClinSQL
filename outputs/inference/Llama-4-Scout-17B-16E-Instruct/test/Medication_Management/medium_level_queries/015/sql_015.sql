WITH 
  -- Define patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 42 AND 52
      AND p.gender = 'M'
      AND a.admission_type = 'Inpatient'
  ),

  -- Identify admissions with diabetes and acute HF
  diabetes_acute_hf AS (
    SELECT 
      subject_id,
      hadm_id
    FROM 
      patients_of_interest
    WHERE 
      hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '250.%'  -- Diabetes
          OR icd_code LIKE '428.%'  -- Acute HF
      )
  ),

  -- Identify medication administration
  medications AS (
    SELECT 
      subject_id,
      hadm_id,
      charttime,
      medication
    FROM 
      `physionet-data.mimiciv_3_1_hosp.emar`
    UNION ALL
    SELECT 
      subject_id,
      hadm_id,
      charttime,
      drug
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
  ),

  -- Classify antidiabetic medications
  antidiabetic_medications AS (
    SELECT 
      subject_id,
      hadm_id,
      charttime,
      medication,
      CASE
        WHEN medication LIKE '%Insulin%' THEN 'Insulin'
        WHEN medication LIKE '%Metformin%' THEN 'Metformin'
        WHEN medication LIKE '%Sulfonylurea%' THEN 'Sulfonylurea'
        WHEN medication LIKE '%DPP-4%' THEN 'DPP-4'
        WHEN medication LIKE '%SGLT2%' THEN 'SGLT2'
        WHEN medication LIKE '%GLP-1%' THEN 'GLP-1'
        WHEN medication LIKE '%TZD%' THEN 'TZD'
        ELSE 'Other'
      END AS antidiabetic_class
    FROM 
      medications
  ),

  -- Calculate prevalence in first 24h and final 12h
  prevalence AS (
    SELECT 
      antidiabetic_class,
      CASE
        WHEN charttime BETWEEN admittime AND admittime + INTERVAL 1 DAY THEN 'first_24h'
        WHEN charttime BETWEEN dischtime - INTERVAL 12 HOUR AND dischtime THEN 'final_12h'
      END AS time_interval,
      COUNT(DISTINCT hadm_id) / (SELECT COUNT(*) FROM diabetes_acute_hf) * 100 AS prevalence
    FROM 
      antidiabetic_medications
    JOIN 
      patients_of_interest
    ON 
      antidiabetic_medications.subject_id = patients_of_interest.subject_id
      AND antidiabetic_medications.hadm_id = patients_of_interest.hadm_id
    JOIN 
      diabetes_acute_hf
    ON 
      patients_of_interest.hadm_id = diabetes_acute_hf.hadm_id
    WHERE 
      antidiabetic_class IN ('Insulin', 'Metformin', 'Sulfonylurea', 'DPP-4', 'SGLT2', 'GLP-1', 'TZD')
    GROUP BY 
      antidiabetic_class,
      time_interval
  ),

  -- Calculate net change
  net_change AS (
    SELECT 
      antidiabetic_class,
      first_24h_prevalence,
      final_12h_prevalence,
      final_12h_prevalence - first_24h_prevalence AS net_change
    FROM 
      (
        SELECT 
          antidiabetic_class,
          MAX(CASE WHEN time_interval = 'first_24h' THEN prevalence END) AS first_24h_prevalence,
          MAX(CASE WHEN time_interval = 'final_12h' THEN prevalence END) AS final_12h_prevalence
        FROM 
          prevalence
        GROUP BY 
          antidiabetic_class
      ) t
  )

SELECT 
  antidiabetic_class,
  first_24h_prevalence,
  final_12h_prevalence,
  net_change
FROM 
  net_change
ORDER BY 
  antidiabetic_class;