WITH stroke_subjects AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%stroke%'
),
eligible_subjects AS (
  SELECT s.subject_id
  FROM stroke_subjects s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_subjects e
    ON a.subject_id = e.subject_id
),
first_adm AS (
  -- Keep only the first admission per subject
  SELECT subject_id, hadm_id
  FROM first_admissions
  WHERE rn = 1
),
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_adm f
    ON i.subject_id = f.subject_id
   AND i.hadm_id = f.hadm_id
),
los_values AS (
  -- Select the LOS of the first ICU stay for each subject
  SELECT los
  FROM first_icu_stays
  WHERE rn = 1
)
-- Compute the IQR using approximate quartiles
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM los_values
);