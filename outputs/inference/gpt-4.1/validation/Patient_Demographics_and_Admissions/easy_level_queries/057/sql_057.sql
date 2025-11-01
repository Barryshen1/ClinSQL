WITH stroke_patients AS (
  -- Get patients with stroke diagnosis
  SELECT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    -- ICD-10 stroke: I60-I64; ICD-9 stroke: 431, 433.x, 434.x, 436
    (
      (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I6[0-4]'))
      OR
      (di.icd_version = 9 AND (
        di.icd_code = '431'
        OR di.icd_code = '436'
        OR REGEXP_CONTAINS(di.icd_code, r'^433')
        OR REGEXP_CONTAINS(di.icd_code, r'^434')
      ))
    )
),
first_admissions AS (
  -- Get first hospital admission for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),
eligible_patients AS (
  -- Filter for male patients aged 46-56 at first admission with stroke
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime
  FROM
    first_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON fa.subject_id = p.subject_id
    JOIN stroke_patients sp
      ON fa.subject_id = sp.subject_id AND fa.hadm_id = sp.hadm_id
  WHERE
    fa.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),
first_icu_stays AS (
  -- Get first ICU stay for each first admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
),
final_cohort AS (
  -- Join eligible patients to their first ICU stay
  SELECT
    ep.subject_id,
    ep.hadm_id,
    fis.stay_id,
    fis.los
  FROM
    eligible_patients ep
    JOIN first_icu_stays fis
      ON ep.subject_id = fis.subject_id AND ep.hadm_id = fis.hadm_id
  WHERE
    fis.rn = 1
    AND fis.los IS NOT NULL
)
SELECT
  -- Calculate IQR of ICU LOS in days
  quantiles[OFFSET(2)] - quantiles[OFFSET(0)] AS icu_los_iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM
    final_cohort
);