WITH pneumonia_admissions AS (
  -- Identify admissions with pneumonia (ICD9 480-486 or ICD10 pneumonia via long_title)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (di.icd_version = 9 AND di.icd_code BETWEEN '480' AND '486')
     OR (di.icd_version = 10 AND LOWER(dd.long_title) LIKE '%pneumonia%')
),
first_admissions AS (
  -- For those admissions, pick the first admission per subject (earliest admittime)
  SELECT p.subject_id, a.hadm_id, a.admittime,
         ROW_NUMBER() OVER (
           PARTITION BY p.subject_id
           ORDER BY a.admittime ASC
         ) AS rn
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pa.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pa.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_admission_per_subject AS (
  -- Keep only the earliest admission per subject
  SELECT subject_id, hadm_id
  FROM first_admissions
  WHERE rn = 1
),
first_icustay AS (
  -- For each subject's first pneumonia admission, get the first ICU stay and its LOS
  SELECT fa.subject_id, fa.hadm_id, ic.los
  FROM first_admission_per_subject fa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON ic.subject_id = fa.subject_id
   AND ic.hadm_id = fa.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY fa.subject_id ORDER BY ic.intime ASC) = 1
)
SELECT quantiles[OFFSET(1)] AS p25_first_admission_icu_los_days
FROM (
  SELECT APPROX_QUANTILES(los, 4) AS quantiles
  FROM first_icustay
) AS q;