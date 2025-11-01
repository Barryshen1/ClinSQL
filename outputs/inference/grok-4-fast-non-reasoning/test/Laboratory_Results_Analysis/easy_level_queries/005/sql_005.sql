WITH male_icu_admissions AS (
  -- Male patients with ICU admissions
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (p.dod IS NULL OR a.hadm_id IS NOT NULL)  -- Exclude deceased without admissions, but keep if they have hosp data
),
index_icu_stays AS (
  -- Index (first) ICU stay per admission
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY stay_id) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM male_icu_admissions)
  )
  WHERE rn = 1
),
sodium_itemids AS (
  -- Identify serum sodium itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%sodium%'
    AND category = 'Chemistry'
),
first_sodium AS (
  -- First serum sodium per index ICU admission
  SELECT 
    mia.subject_id,
    mia.hadm_id,
    le.valuenum AS first_sodium
  FROM male_icu_admissions mia
  INNER JOIN index_icu_stays iis
    ON mia.hadm_id = iis.hadm_id
  INNER JOIN (
    -- Subquery for first charttime of sodium post-ICU intime
    SELECT 
      le.subject_id,
      le.hadm_id,
      MIN(le.charttime) AS first_time
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN sodium_itemids si
      ON le.itemid = si.itemid
    INNER JOIN index_icu_stays iis2
      ON le.hadm_id = iis2.hadm_id
    WHERE le.charttime >= iis2.intime
      AND le.valuenum IS NOT NULL
      AND le.valuenum BETWEEN 100 AND 200  -- Reasonable range for serum Na (mmol/L)
    GROUP BY le.subject_id, le.hadm_id
  ) first_time_sub
    ON mia.subject_id = first_time_sub.subject_id
    AND mia.hadm_id = first_time_sub.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON first_time_sub.subject_id = le.subject_id
    AND first_time_sub.hadm_id = le.hadm_id
    AND first_time_sub.first_time = le.charttime
    AND le.itemid IN (SELECT itemid FROM sodium_itemids)
)
-- Compute IQR of first serum sodium values
SELECT
  PERCENTILE_CONT(first_sodium, 0.25) AS q1_sodium,
  PERCENTILE_CONT(first_sodium, 0.75) AS q3_sodium,
  (PERCENTILE_CONT(first_sodium, 0.75) - PERCENTILE_CONT(first_sodium, 0.25)) AS iqr_sodium,
  COUNT(*) AS num_admissions
FROM first_sodium;