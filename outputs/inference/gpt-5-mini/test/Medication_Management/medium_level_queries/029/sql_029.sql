WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    -- require both diagnoses to appear for the same admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%diabetes%'
        AND (
          LOWER(di.long_title) LIKE '%type 2%'
          OR LOWER(di.long_title) LIKE '%type ii%'
          OR LOWER(di.long_title) LIKE '%typeii%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%heart failure%'
    )
    -- ensure discharge time present for last-72h calculation
    AND a.dischtime IS NOT NULL
),

-- Gather medication orders/records from prescriptions and pharmacy
raw_meds AS (
  SELECT
    subject_id,
    hadm_id,
    starttime AS starttime,
    stoptime AS stoptime,
    drug AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    starttime AS starttime,
    stoptime AS stoptime,
    medication AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
),

-- Map free-text medication names to drug classes of interest
meds_mapped AS (
  SELECT
    rm.*,
    CASE
      WHEN LOWER(med_text) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(med_text) LIKE '%metformin%' THEN 'metformin'
      WHEN REGEXP_CONTAINS(LOWER(med_text), r'glipizide|glyburide|glibenclamide|glimepiride|tolbutamide|chlorpropamide') THEN 'sulfonylurea'
      WHEN REGEXP_CONTAINS(LOWER(med_text), r'sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin') THEN 'dpp4'
      WHEN REGEXP_CONTAINS(LOWER(med_text), r'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin') THEN 'sglt2'
      WHEN REGEXP_CONTAINS(LOWER(med_text), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide') THEN 'glp1'
      WHEN REGEXP_CONTAINS(LOWER(med_text), r'pioglitazone|rosiglitazone') THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM raw_meds rm
  WHERE rm.hadm_id IS NOT NULL
),

-- Restrict to cohort admissions and consider overlap with first/last 72-hour windows
meds_in_windows AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    m.drug_class,
    -- compute window boundaries
    c.admittime AS admittime,
    c.dischtime AS dischtime,
    TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) AS first_window_end,
    TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AS last_window_start,
    -- medication times
    m.starttime,
    m.stoptime,
    -- flags for overlap
    -- first 72 hours overlap:
    CASE
      WHEN m.starttime IS NOT NULL
       AND m.drug_class IS NOT NULL
       AND m.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (m.stoptime IS NULL OR m.stoptime > c.admittime)
      THEN 1 ELSE 0
    END AS in_first_72h,
    -- last 72 hours overlap:
    CASE
      WHEN m.starttime IS NOT NULL
       AND m.drug_class IS NOT NULL
       AND m.starttime < c.dischtime
       AND (m.stoptime IS NULL OR m.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
      THEN 1 ELSE 0
    END AS in_last_72h
  FROM cohort c
  JOIN meds_mapped m
    ON m.hadm_id = c.hadm_id
  WHERE m.drug_class IS NOT NULL
),

-- For each admission and drug class, determine whether there was any exposure in the windows
per_admission_class AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(in_first_72h) AS any_in_first_72h,
    MAX(in_last_72h)  AS any_in_last_72h
  FROM meds_in_windows
  GROUP BY hadm_id, drug_class
),

-- Aggregate across admissions to produce counts and percents
summary AS (
  SELECT
    pac.drug_class,
    COUNT(DISTINCT pac.hadm_id) AS n_admissions_exposed_anywhere,
    SUM(pac.any_in_first_72h) AS n_first_72h,
    SUM(pac.any_in_last_72h) AS n_last_72h
  FROM per_admission_class pac
  GROUP BY pac.drug_class
),

denominator AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_cohort_admissions
  FROM cohort
)

SELECT
  s.drug_class,
  d.n_cohort_admissions AS cohort_n_admissions,
  s.n_first_72h,
  ROUND(100.0 * s.n_first_72h / d.n_cohort_admissions, 2) AS pct_first_72h,
  s.n_last_72h,
  ROUND(100.0 * s.n_last_72h / d.n_cohort_admissions, 2) AS pct_last_72h
FROM summary s
CROSS JOIN denominator d
ORDER BY
  CASE s.drug_class
    WHEN 'insulin' THEN 1
    WHEN 'metformin' THEN 2
    WHEN 'sulfonylurea' THEN 3
    WHEN 'dpp4' THEN 4
    WHEN 'sglt2' THEN 5
    WHEN 'glp1' THEN 6
    WHEN 'tzd' THEN 7
    ELSE 99
  END;