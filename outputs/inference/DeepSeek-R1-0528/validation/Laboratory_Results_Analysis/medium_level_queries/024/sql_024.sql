WITH chest_pain_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate age at admission using anchor_year and anchor_age
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pt.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '7865%')  -- ICD-9 chest pain
      OR (diag.icd_version = 10 AND diag.icd_code IN ('R071','R072','R073','R074','R078','R079'))  -- ICD-10 chest pain (excludes R070)
    )
),
filtered_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag
  FROM
    chest_pain_admissions
  WHERE
    age_at_admission BETWEEN 64 AND 74  -- Age filter
),
first_troponin AS (
  SELECT
    hadm_id,
    charttime,
    valuenum AS troponin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 51003  -- hs-Troponin T
    AND valuenum IS NOT NULL
    AND valueuom = 'ng/mL'  -- Ensure correct unit
    AND hadm_id IS NOT NULL
),
ranked_troponin AS (
  SELECT
    hadm_id,
    troponin_value,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn  -- Rank by earliest measurement
  FROM
    first_troponin
),
valid_troponin_admissions AS (
  SELECT
    f.hadm_id,
    f.troponin_value
  FROM
    ranked_troponin f
  WHERE
    rn = 1  -- First troponin measurement
    AND f.troponin_value > 0.014  -- Exceeds 99th percentile
),
cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag,
    vt.troponin_value
  FROM
    filtered_admissions fa
  INNER JOIN
    valid_troponin_admissions vt
    ON fa.hadm_id = vt.hadm_id
)
SELECT
  COUNT(*) AS total_admissions,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
  MIN(troponin_value) AS troponin_min,
  MAX(troponin_value) AS troponin_max,
  AVG(troponin_value) AS troponin_avg,
  STDDEV(troponin_value) AS troponin_std,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS troponin_25p,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(2)] AS troponin_50p,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS troponin_75p
FROM
  cohort;