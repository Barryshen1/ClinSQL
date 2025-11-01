WITH sepsis_patients AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code IN ('99591', '99592')))
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R652%'))
  GROUP BY d.hadm_id
),

filtered_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission using MIMIC-IV standard approach
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 66 AND 76
),

first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS icu_stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),

cohort AS (
  SELECT 
    fps.subject_id,
    fps.hadm_id,
    fis.stay_id,
    fis.intime
  FROM filtered_patients fps
  INNER JOIN sepsis_patients sp ON fps.hadm_id = sp.hadm_id
  INNER JOIN first_icu_stays fis ON fps.subject_id = fis.subject_id AND fps.hadm_id = fis.hadm_id
  WHERE fis.icu_stay_order = 1
),

procedure_counts AS (
  SELECT 
    c.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p 
    ON c.stay_id = p.stay_id
    AND p.starttime >= c.intime 
    AND p.starttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
)

SELECT 
  APPROX_QUANTILES(distinct_procedure_count, 1000)[OFFSET(900)] AS percentile_90
FROM procedure_counts;