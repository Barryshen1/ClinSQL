WITH aki_admissions AS (
  -- Find all admissions with an AKI diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    LOWER(diag.long_title) LIKE '%acute kidney injury%'
    OR LOWER(diag.long_title) LIKE '%acute renal failure%'
),

female_midage_aki AS (
  -- Restrict to female patients aged 48–58 at admission who had AKI
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN aki_admissions ak
      ON a.subject_id = ak.subject_id
      AND a.hadm_id = ak.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

icu_stays_filtered AS (
  -- Get ICU stays for the filtered admissions
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN female_midage_aki f
      ON s.subject_id = f.subject_id
      AND s.hadm_id = f.hadm_id
  WHERE
    s.los IS NOT NULL
    AND s.los > 0
)

-- Compute the 25th percentile ICU LOS in days
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile_days
FROM
  icu_stays_filtered;