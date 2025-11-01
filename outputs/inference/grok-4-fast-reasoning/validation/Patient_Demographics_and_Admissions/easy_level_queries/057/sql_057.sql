WITH first_admittimes AS (
  SELECT 
    subject_id, 
    MIN(admittime) AS first_admittime, 
    MIN(hadm_id) AS first_hadm_id  -- Handle rare ties on admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY subject_id
),
first_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_admittimes fa 
    ON a.subject_id = fa.subject_id 
    AND a.hadm_id = fa.first_hadm_id
),
stroke_first_admissions AS (
  SELECT DISTINCT 
    fa.subject_id, 
    fa.hadm_id, 
    fa.admittime
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON fa.subject_id = d.subject_id 
    AND fa.hadm_id = d.hadm_id
  WHERE (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
     OR (d.icd_version = 9 AND CAST(d.icd_code AS INT64) BETWEEN 430 AND 438)
),
patients_with_stroke_first AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    sfa.hadm_id, 
    sfa.admittime,
    SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM sfa.admittime) - p.anchor_year AS INT64) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN stroke_first_admissions sfa 
    ON p.subject_id = sfa.subject_id
),
filtered_patients AS (
  SELECT *
  FROM patients_with_stroke_first
  WHERE gender = 'M'
    AND age_at_admit BETWEEN 46 AND 56
),
icu_los AS (
  SELECT 
    fp.subject_id, 
    SUM(i.los) AS total_icu_los
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON fp.subject_id = i.subject_id 
    AND fp.hadm_id = i.hadm_id
  GROUP BY fp.subject_id
  HAVING total_icu_los > 0
)
SELECT 
  APPROX_QUANTILES(total_icu_los, 4)[OFFSET(3)] - APPROX_QUANTILES(total_icu_los, 4)[OFFSET(1)] AS iqr_days
FROM icu_los;