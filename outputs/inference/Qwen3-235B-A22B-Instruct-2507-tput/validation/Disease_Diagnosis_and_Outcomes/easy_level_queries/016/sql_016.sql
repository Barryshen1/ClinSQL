WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days as a decimal
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
admission_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  WHERE
    di.icd_version = 10
),
pneumonia_copd_admissions AS (
  SELECT
    pa.hadm_id
  FROM
    patient_admissions pa
  INNER JOIN
    admission_diagnoses ad
  ON
    pa.hadm_id = ad.hadm_id
  WHERE
    pa.age_at_admit >= 68
    AND pa.age_at_admit <= 78
    AND (
      (ad.icd_code LIKE 'J18%' OR ad.icd_code = 'J159' OR ad.icd_code = 'J168' OR ad.icd_code LIKE 'J17%') -- pneumonia
      OR ad.icd_code LIKE 'J44%' -- COPD
    )
  GROUP BY
    pa.hadm_id
  HAVING
    -- Ensure at least one pneumonia code and one COPD code
    SUM(CASE WHEN ad.icd_code LIKE 'J18%' OR ad.icd_code = 'J159' OR ad.icd_code = 'J168' OR ad.icd_code LIKE 'J17%' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN ad.icd_code LIKE 'J44%' THEN 1 ELSE 0 END) > 0
)
SELECT
  APPROX_QUANTILES(pa.los_days, 1000)[OFFSET(750)] AS hospital_los_75th_percentile
FROM
  patient_admissions pa
INNER JOIN
  pneumonia_copd_admissions pca
ON
  pa.hadm_id = pca.hadm_id;