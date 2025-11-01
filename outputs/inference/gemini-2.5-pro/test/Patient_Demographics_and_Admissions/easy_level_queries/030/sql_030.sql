WITH first_admissions_filtered AS (
  -- Step 1: Identify the first hospital admission for female patients aged 52-62.
  SELECT
    ad.subject_id,
    ad.hadm_id,
    ad.admittime,
    ad.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pt
  INNER JOIN (
    -- Subquery to rank admissions by time for each patient
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) AS ad
    ON pt.subject_id = ad.subject_id
  WHERE
    ad.rn = 1 -- Filter for the first admission
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 52 AND 62
),

anticoagulant_admissions AS (
  -- Step 2: Identify hospital admissions where anticoagulants were prescribed.
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- A non-exhaustive but common list of anticoagulants (generic and brand names)
    LOWER(drug) LIKE '%heparin%'
    OR LOWER(drug) LIKE '%warfarin%'
    OR LOWER(drug) LIKE '%enoxaparin%'
    OR LOWER(drug) LIKE '%lovenox%'
    OR LOWER(drug) LIKE '%rivaroxaban%'
    OR LOWER(drug) LIKE '%xarelto%'
    OR LOWER(drug) LIKE '%apixaban%'
    OR LOWER(drug) LIKE '%eliquis%'
    OR LOWER(drug) LIKE '%dabigatran%'
    OR LOWER(drug) LIKE '%pradaxa%'
    OR LOWER(drug) LIKE '%argatroban%'
    OR LOWER(drug) LIKE '%bivalirudin%'
    OR LOWER(drug) LIKE '%fondaparinux%'
    OR LOWER(drug) LIKE '%arixtra%'
)

-- Step 3: Calculate the standard deviation of LOS for the final cohort.
SELECT
  STDDEV(DATETIME_DIFF(faf.dischtime, faf.admittime, DAY)) AS sd_los_days
FROM first_admissions_filtered AS faf
-- Join with anticoagulant admissions to ensure the patient received the medication
INNER JOIN anticoagulant_admissions AS aa
  ON faf.hadm_id = aa.hadm_id;