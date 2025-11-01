WITH admissions_with_icu AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
    WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  )
),
stroke AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN icd_version = 10 AND icd_code LIKE 'I63%' THEN 'ischemic'
      WHEN icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%') THEN 'hemorrhagic'
      WHEN icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code = '436') THEN 'ischemic'
      WHEN icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%') THEN 'hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
),
comorb AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_comorb
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    s.stroke_type,
    CASE 
      WHEN a.los_days <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group,
    CASE 
      WHEN COALESCE(c.num_comorb, 0) <= 1 THEN 'low'
      WHEN COALESCE(c.num_comorb, 0) <= 4 THEN 'med'
      ELSE 'high'
    END AS comorb_group
  FROM admissions_with_icu a
  INNER JOIN stroke s 
    ON a.hadm_id = s.hadm_id 
    AND s.stroke_type IS NOT NULL
  LEFT JOIN comorb c 
    ON a.hadm_id = c.hadm_id
  WHERE a.gender = 'M' 
    AND a.age BETWEEN 44 AND 54
),
vent_hadm AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON ce.stay_id = i.stay_id
  WHERE ce.itemid IN (720, 223848, 223849, 224008, 224069, 224396, 224397, 224435, 224436, 224444, 224455, 224456, 224457)
),
vasop_hadm AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON ie.stay_id = i.stay_id
  WHERE ie.itemid IN (221906, 222315, 225798, 220661, 220242, 220543)  -- norepinephrine, vasopressin, phenylephrine, epinephrine, dopamine, dobutamine
    AND ((ie.amount IS NOT NULL AND ie.amount > 0) OR (ie.rate IS NOT NULL AND ie.rate > 0))
),
rrt_hadm AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON pe.stay_id = i.stay_id
  WHERE pe.itemid IN (225826, 228353, 228354, 228537, 228538, 228539, 228540)  -- hemodialysis, SLEDD, SCUF, CVVH, CVVHD, CVVHDF, isolated UF
),
cohort_flags AS (
  SELECT 
    c.*,
    CASE WHEN v.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent,
    CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasop,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt
  FROM cohort c
  LEFT JOIN vent_hadm v ON c.hadm_id = v.hadm_id
  LEFT JOIN vasop_hadm vp ON c.hadm_id = vp.hadm_id
  LEFT JOIN rrt_hadm r ON c.hadm_id = r.hadm_id
)
SELECT 
  stroke_type,
  los_group,
  comorb_group,
  COUNT(*) AS n,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(AVG(mech_vent) * 100, 2) AS pct_mech_vent,
  ROUND(AVG(vasop) * 100, 2) AS pct_vasopressors,
  ROUND(AVG(rrt) * 100, 2) AS pct_rrt
FROM cohort_flags
GROUP BY stroke_type, los_group, comorb_group
ORDER BY stroke_type, los_group, comorb_group;