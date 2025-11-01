WITH 
  -- Identify AKI patients based on serum creatinine levels
  aki_patients AS (
    SELECT 
      le.subject_id, 
      le.hadm_id,
      MAX(CASE WHEN le.itemid = 220050 AND le.valuenum > 1.5 THEN 1 ELSE 0 END) AS has_aki
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    GROUP BY 
      le.subject_id, 
      le.hadm_id
  ),

  -- Identify CNS-depressant and nephrotoxic drugs
  drug_classifications AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      p.drug,
      CASE 
        WHEN LOWER(p.drug) LIKE '%benzodiazepine%' OR LOWER(p.drug) LIKE '%opiate%' THEN 'CNS-depressant'
        WHEN LOWER(p.drug) LIKE '%nsaid%' OR LOWER(p.drug) LIKE '%aminoglycoside%' THEN 'nephrotoxic'
        ELSE 'other'
      END AS drug_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ),

  -- Calculate medication complexity score (simple count for demonstration)
  medication_complexity AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT drug) AS complexity_score
    FROM 
      drug_classifications
    GROUP BY 
      subject_id,
      hadm_id
  ),

  -- Patient demographics and outcomes
  patient_outcomes AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      ic.stay_id,
      ic.intime AS icu_intime,
      ic.outtime AS icu_outtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  )

-- Final query
SELECT 
  p.gender,
  p.anchor_age,
  ac.has_aki,
  dc.drug_category,
  mc.complexity_score,
  po.hospital_expire_flag,
  EXTRACT(DAY FROM po.dischtime - po.admittime) AS los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN 
  patient_outcomes po ON p.subject_id = po.subject_id
JOIN 
  aki_patients ac ON p.subject_id = ac.subject_id AND po.hadm_id = ac.hadm_id
JOIN 
  medication_complexity mc ON p.subject_id = mc.subject_id AND po.hadm_id = mc.hadm_id
JOIN 
  drug_classifications dc ON p.subject_id = dc.subject_id AND po.hadm_id = dc.hadm_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 81 AND 91
  AND ac.has_aki = 1;