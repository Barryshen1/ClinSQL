WITH pneumonia_icd AS (
  -- ICD-9: 480–486, ICD-10: J12–J18
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]$'))
    OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]'))
),
first_admissions AS (
  -- Get each male patient aged 51–61's first hospital admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
pneumonia_admissions AS (
  -- Filter first admissions for pneumonia diagnosis
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  JOIN pneumonia_icd pi
    ON d.icd_code = pi.icd_code AND d.icd_version = pi.icd_version
  GROUP BY fa.subject_id, fa.hadm_id, fa.admittime
),
first_icu_stays AS (
  -- For each qualifying admission, get the first ICU stay
  SELECT
    pa.subject_id,
    pa.hadm_id,
    MIN(icu.stay_id) AS stay_id
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pa.subject_id = icu.subject_id AND pa.hadm_id = icu.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id
),
icu_los AS (
  -- Get LOS for each first ICU stay
  SELECT
    fis.subject_id,
    fis.hadm_id,
    icu.stay_id,
    icu.los
  FROM first_icu_stays fis
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON fis.stay_id = icu.stay_id
  WHERE icu.los IS NOT NULL AND icu.los > 0
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile
FROM icu_los
;