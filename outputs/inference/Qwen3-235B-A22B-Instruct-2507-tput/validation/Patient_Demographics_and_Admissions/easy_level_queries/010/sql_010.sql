WITH aki_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute kidney%'
     OR LOWER(long_title) LIKE '%akf%'
     OR LOWER(long_title) LIKE '%acute renal%'
),
aki_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN aki_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  GROUP BY di.hadm_id
),
patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
filtered_patients AS (
  SELECT pa.subject_id, pa.hadm_id
  FROM patient_age pa
  WHERE pa.gender = 'F'
    AND pa.age_at_admission >= 48
    AND pa.age_at_admission <= 58
)
SELECT
  APPROX_QUANTILES(i.los, 100)[OFFSET(25)] AS icu_los_25th_percentile
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN filtered_patients fp
  ON i.hadm_id = fp.hadm_id
INNER JOIN aki_admissions aa
  ON i.hadm_id = aa.hadm_id;