WITH target_population AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i 
    ON p.subject_id = i.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a 
    ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 40 AND 50
),

hemorrhagic_stroke_diagnoses AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code 
    AND di.icd_version = did.icd_version
  WHERE 
    LOWER(did.long_title) LIKE '%hemorrhagic stroke%'
    OR LOWER(did.long_title) LIKE '%intracerebral hemorrhage%'
    OR LOWER(did.long_title) LIKE '%subarachnoid hemorrhage%'
    OR LOWER(did.long_title) LIKE '%intracranial hemorrhage%'
    OR LOWER(did.long_title) LIKE '%cerebral hemorrhage%'
    OR LOWER(did.long_title) LIKE '%intracerebral bleed%'
    OR LOWER(did.long_title) LIKE '%subarachnoid bleed%'
),

diagnostic_procedures AS (
  SELECT 
    pe.stay_id,
    COUNT(*) AS procedure_count_72h
  FROM 
    physionet-data.mimiciv_3_1_icu.procedureevents pe
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON pe.stay_id = i.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) IN (
      'ct head w/o contrast',
      'ct head w/ contrast',
      'ct angiography head',
      'ct angiogram head',
      'mri brain',
      'lumbar puncture',
      'cerebral angiography',
      'cerebral angiogram',
      'ct c-spine',
      'ct c-spine w/o contrast',
      'ct c-spine w/ contrast'
    )
    AND pe.charttime >= i.intime
    AND pe.charttime <= i.intime + INTERVAL 72 HOUR
  GROUP BY 
    pe.stay_id
),

procedure_counts AS (
  SELECT 
    tp.subject_id,
    tp.stay_id,
    COALESCE(dp.procedure_count_72h, 0) AS procedure_count_72h,
    tp.los,
    tp.hospital_expire_flag
  FROM 
    target_population tp
  LEFT JOIN 
    diagnostic_procedures dp
    ON tp.stay_id = dp.stay_id
)

SELECT 
  CASE 
    WHEN hsd.subject_id IS NOT NULL THEN 'hemorrhagic_stroke'
    ELSE 'other'
  END AS hemorrhagic_stroke_group,
  PERCENTILE_CONT(procedure_count_72h, 0.9) AS p90_procedures_72h,
  MEDIAN(los) AS median_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM 
  procedure_counts pc
LEFT JOIN 
  hemorrhagic_stroke_diagnoses hsd 
  ON pc.subject_id = hsd.subject_id AND pc.hadm_id = hsd.hadm_id
GROUP BY 
  hemorrhagic_stroke_group;