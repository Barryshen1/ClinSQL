WITH 
-- Calculate Charlson score
charlson_scores AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    SUM(CASE 
      WHEN d.icd_code IN ('401', '402', '403', '404', '405') THEN 1 
      WHEN d.icd_code IN ('410', '411', '412', '413', '414') THEN 1 
      WHEN d.icd_code IN ('420', '421', '422') THEN 1 
      WHEN d.icd_code IN ('430', '431', '432', '433', '434', '435', '436') THEN 1 
      WHEN d.icd_code IN ('440', '441', '442', '443', '444', '445') THEN 1 
      WHEN d.icd_code IN ('446', '447', '448') THEN 1 
      WHEN d.icd_code IN ('449') THEN 1 
      ELSE 0 
    END) AS charlson_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  GROUP BY 
    a.subject_id, a.hadm_id
),

-- Identify ICU stays
icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    first_careunit,
    last_careunit,
    intime,
    outtime,
    los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Patient data
patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'non-ICU'
    END AS care_unit,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COALESCE(cs.charlson_score, 0) AS charlson_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  LEFT JOIN 
    icu_stays i
  ON 
    a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN 
    charlson_scores cs
  ON 
    a.subject_id = cs.subject_id AND a.hadm_id = cs.hadm_id
  WHERE 
    a.admission_type = 'postoperative'
    AND p.gender = 'M'
    AND p.anchor_age = 44
),

-- Interventions
interventions AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid,
    value
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (
      220050,  -- Mechanical Ventilation
      220179,  -- Vasopressors
      221900   -- RRT
    )
)

SELECT 
  pd.care_unit,
  CASE 
    WHEN pd.los_days <= 3 THEN '<=3'
    WHEN pd.los_days BETWEEN 4 AND 6 THEN '4-6'
    WHEN pd.los_days BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_category,
  CASE 
    WHEN pd.charlson_score <= 3 THEN '<=3'
    WHEN pd.charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_category,
  SUM(pd.hospital_expire_flag) / COUNT(*) AS mortality_rate,
  SUM(CASE 
    WHEN i.itemid = 220050 THEN 1 
    ELSE 0 
  END) / COUNT(DISTINCT pd.hadm_id) AS mech_vent_rate,
  SUM(CASE 
    WHEN i.itemid = 220179 THEN 1 
    ELSE 0 
  END) / COUNT(DISTINCT pd.hadm_id) AS vasopressor_rate,
  SUM(CASE 
    WHEN i.itemid = 221900 THEN 1 
    ELSE 0 
  END) / COUNT(DISTINCT pd.hadm_id) AS rrt_rate
FROM 
  patient_data pd
  LEFT JOIN interventions i
  ON pd.subject_id = i.subject_id AND pd.hadm_id = i.hadm_id
GROUP BY 
  pd.care_unit,
  los_category,
  charlson_category;