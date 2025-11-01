WITH stroke_patients AS (
  -- Stroke admissions for male patients aged 46-56
  SELECT p.subject_id, d.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 46 AND 56
    AND LOWER(di.long_title) LIKE '%stroke%'
),
first_stroke_admission AS (
  -- For each patient, keep only the earliest stroke admission
  SELECT subject_id, hadm_id, admittime
  FROM (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM stroke_patients AS s
  )
  WHERE rn = 1
),
first_icu_stay AS (
  -- For each (subject_id, hadm_id) keep the first ICU stay (earliest intime)
  SELECT f.subject_id, f.hadm_id,
         i.intime AS first_intime, i.outtime AS first_outtime
  FROM first_stroke_admission AS f
  JOIN (
    SELECT subject_id, hadm_id, intime, outtime,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) AS i
    ON i.subject_id = f.subject_id
   AND i.hadm_id = f.hadm_id
   AND i.rn = 1
),
los AS (
  -- Compute LOS in days for the first ICU stay of the first stroke admission
  SELECT subject_id, hadm_id,
         TIMESTAMP_DIFF(first_outtime, first_intime, SECOND) / 86400.0 AS los_days
  FROM first_icu_stay
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_days
FROM los;