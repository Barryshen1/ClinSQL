WITH pneumonia_admissions AS (
  -- Admissions with pneumonia diagnosis
  SELECT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 pneumonia: J12-J18
      (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486, only numeric codes
      OR (
        di.icd_version = 9
        AND REGEXP_CONTAINS(di.icd_code, r'^[0-9]+$')
        AND CAST(di.icd_code AS INT64) BETWEEN 480 AND 486
      )
    )
),
 cohort AS (
  -- Men aged 43-53 with pneumonia, first ICU stay per patient
  SELECT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.los,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN pneumonia_admissions pa
      ON p.subject_id = pa.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON pa.subject_id = i.subject_id AND pa.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),
 first_icu_stays AS (
  -- For each patient, select their first ICU stay (by intime)
  SELECT
    subject_id,
    anchor_age,
    stay_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM
    cohort
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER () AS los_25th_percentile
FROM
  first_icu_stays
WHERE
  rn = 1
;