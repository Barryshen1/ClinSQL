WITH aki_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code IN ('N170', 'N171', 'N172', 'N178', 'N179')
),
filtered_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN 48 AND 58
),
eligible_stays AS (
  SELECT 
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN filtered_patients fp
    ON i.subject_id = fp.subject_id AND i.hadm_id = fp.hadm_id
  INNER JOIN aki_admissions aa
    ON fp.hadm_id = aa.hadm_id
)
SELECT 
  APPROX_QUANTILES(los, 1001)[OFFSET(250)] AS icu_los_25th_percentile
FROM eligible_stays;