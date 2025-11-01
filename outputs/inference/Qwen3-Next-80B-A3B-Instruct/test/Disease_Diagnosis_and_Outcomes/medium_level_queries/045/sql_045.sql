WITH pneumonia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '≤7 days'
      ELSE '>7 days'
    END AS los_category
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('480','481','482','483','484','485','486'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('J12','J13','J14','J15','J16','J17','J18','J690'))
    )
    AND (
      LOWER(d_icd.long_title) LIKE '%pneumonia%'
      AND (
        LOWER(d_icd.long_title) LIKE '%community%' 
        OR LOWER(d_icd.long_title) LIKE '%aspiration%' 
        OR LOWER(d_icd.long_title) LIKE '%aspirat%'
      )
    )
),
icu_day1 AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    CASE 
      WHEN i.intime IS NOT NULL 
        AND i.intime <= TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR) 
      THEN 1 
      ELSE 0 
    END AS day1_icu
  FROM pneumonia_patients p
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
),
mech_vent AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    1 AS mech_vent
  FROM pneumonia_patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON p.subject_id = pe.subject_id AND p.hadm_id = pe.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%mechanical ventilation%'
),
vasopressor AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    1 AS vasopressor
  FROM pneumonia_patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON p.subject_id = ie.subject_id AND p.hadm_id = ie.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) IN ('norepinephrine', 'epinephrine', 'vasopressin')
),
rrt AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    1 AS rrt
  FROM pneumonia_patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON p.subject_id = pe.subject_id AND p.hadm_id = pe.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%renal replacement therapy%' 
    OR LOWER(di.label) LIKE '%dialysis%'
)
SELECT
  pp.los_category,
  COALESCE(id.day1_icu, 0) AS day1_icu,
  COUNT(*) AS total_patients,
  SUM(pp.hospital_expire_flag) AS in_hospital_deaths,
  AVG(COALESCE(mv.mech_vent, 0)) AS mech_vent_prevalence,
  AVG(COALESCE(v.vasopressor, 0)) AS vasopressor_prevalence,
  AVG(COALESCE(r.rrt, 0)) AS rrt_prevalence
FROM pneumonia_patients pp
LEFT JOIN icu_day1 id ON pp.subject_id = id.subject_id AND pp.hadm_id = id.hadm_id
LEFT JOIN mech_vent mv ON pp.subject_id = mv.subject_id AND pp.hadm_id = mv.hadm_id
LEFT JOIN vasopressor v ON pp.subject_id = v.subject_id AND pp.hadm_id = v.hadm_id
LEFT JOIN rrt r ON pp.subject_id = r.subject_id AND pp.hadm_id = r.hadm_id
GROUP BY pp.los_category, id.day1_icu
ORDER BY pp.los_category, id.day1_icu;