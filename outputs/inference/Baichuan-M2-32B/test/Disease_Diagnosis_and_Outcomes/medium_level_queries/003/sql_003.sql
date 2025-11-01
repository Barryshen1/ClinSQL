WITH eligible_admissions AS (
  SELECT 
    ad.subject_id,
    ad.hadm_id,
    ad.admittime,
    ad.dischtime,
    ad.hospital_expire_flag,
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) AS hospital_los,
    CASE 
      WHEN di.icd_code LIKE 'I63%' THEN 'ischemic'
      WHEN di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' THEN 'hemorrhagic'
      ELSE NULL 
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON ad.subject_id = pa.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id AND di.seq_num = 1
  WHERE 
    pa.gender = 'M'
    AND TIMESTAMP_DIFF(ad.admittime, 
        DATE(pa.anchor_year, 1, 1) - INTERVAL pa.anchor_age YEAR, 
        YEAR) BETWEEN 44 AND 54
    AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR di.icd_code LIKE 'I63%')
),
comorbidity_counts AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code NOT LIKE 'I60%' 
    AND icd_code NOT LIKE 'I61%' 
    AND icd_code NOT LIKE 'I62%' 
    AND icd_code NOT LIKE 'I63%'
  GROUP BY subject_id, hadm_id
),
first_icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(outtime, intime, DAY) AS icu_los
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) ranked
  WHERE rn = 1
),
mech_vent AS (
  SELECT 
    subject_id,
    hadm_id,
    1 AS mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%Mechanical Ventilation%'
  )
  GROUP BY subject_id, hadm_id
),
vasopressors AS (
  SELECT 
    subject_id,
    hadm_id,
    1 AS vasopressor
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%norepinephrine%' 
       OR label LIKE '%epinephrine%' 
       OR label LIKE '%dopamine%' 
       OR label LIKE '%vasopressor%'
  )
  GROUP BY subject_id, hadm_id
),
rrt AS (
  SELECT 
    subject_id,
    hadm_id,
    1 AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%dialysis%' 
       OR label LIKE '%CRRT%'
  )
  GROUP BY subject_id, hadm_id
)
SELECT 
  stroke_type,
  comorbidity_level,
  icu_los_group,
  COUNT(*) AS num_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  APPROX_QUANTILES(hospital_los, 100)[SAFE_OFFSET(50)] AS median_los,
  AVG(COALESCE(mech_vent, 0)) * 100 AS pct_mech_vent,
  AVG(COALESCE(vasopressor, 0)) * 100 AS pct_vasopressors,
  AVG(COALESCE(rrt, 0)) * 100 AS pct_rrt
FROM (
  SELECT 
    ea.stroke_type,
    CASE 
      WHEN cc.comorbidity_count BETWEEN 0 AND 2 THEN 'low'
      WHEN cc.comorbidity_count BETWEEN 3 AND 5 THEN 'medium'
      WHEN cc.comorbidity_count >= 6 THEN 'high'
      ELSE 'unknown'
    END AS comorbidity_level,
    CASE 
      WHEN fis.icu_los <= 5 THEN '≤5'
      WHEN fis.icu_los > 5 THEN '>5'
      ELSE 'unknown'
    END AS icu_los_group,
    ea.hospital_expire_flag,
    ea.hospital_los,
    mv.mech_vent,
    vp.vasopressor,
    r.rrt
  FROM eligible_admissions ea
  LEFT JOIN comorbidity_counts cc
    ON ea.subject_id = cc.subject_id AND ea.hadm_id = cc.hadm_id
  LEFT JOIN first_icu_stay fis
    ON ea.subject_id = fis.subject_id AND ea.hadm_id = fis.hadm_id
  LEFT JOIN mech_vent mv
    ON ea.subject_id = mv.subject_id AND ea.hadm_id = mv.hadm_id
  LEFT JOIN vasopressors vp
    ON ea.subject_id = vp.subject_id AND ea.hadm_id = vp.hadm_id
  LEFT JOIN rrt r
    ON ea.subject_id = r.subject_id AND ea.hadm_id = r.hadm_id
  WHERE fis.icu_los IS NOT NULL  -- exclude admissions without ICU stay
)
GROUP BY stroke_type, comorbidity_level, icu_los_group
ORDER BY stroke_type, comorbidity_level, icu_los_group;