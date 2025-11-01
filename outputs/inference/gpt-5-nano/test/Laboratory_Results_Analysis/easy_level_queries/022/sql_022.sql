WITH male_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age >= 18
),

-- 2) Identify arterial blood gas pH measurements in ICU, with robust label filtering
abg_ph AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` isty
    ON ce.subject_id = isty.subject_id
   AND ce.hadm_id = isty.hadm_id
   AND ce.stay_id = isty.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ph%'
    AND (
          LOWER(di.label) LIKE '%arterial%'    -- arterial ABG
          OR LOWER(di.label) LIKE '%blood gas%'  -- generic ABG entries
          OR LOWER(di.label) LIKE '%abg%'          -- ABG-specific labels
        )
    -- Ensure the measurement occurred during the ICU stay
    AND ce.charttime BETWEEN isty.intime AND isty.outtime
),

-- 3) Per-visit (stay) maximum ABG pH
per_visit_max AS (
  SELECT
    iv.subject_id,
    iv.hadm_id,
    iv.stay_id,
    MAX(iv.valuenum) AS pH
  FROM abg_ph iv
  GROUP BY iv.subject_id, iv.hadm_id, iv.stay_id
),

-- 4) Per-patient peak ABG pH (max across all ICU stays for the patient)
per_patient_peak AS (
  SELECT pv.subject_id, MAX(pH) AS peak_pH
  FROM per_visit_max pv
  JOIN male_patients mp
    ON pv.subject_id = mp.subject_id
  GROUP BY pv.subject_id
)

-- 5) Compute IQR of the per-patient peak ABG pH
SELECT
  q25 AS pH_q1,
  q75 AS pH_q3,
  SAFE_DIVIDE(q75 - q25, 1) AS iqr_pH
FROM (
  SELECT
    quantiles[OFFSET(24)] AS q25,  -- 25th percentile
    quantiles[OFFSET(74)] AS q75   -- 75th percentile
  FROM (
    SELECT APPROX_QUANTILES(peak_pH, 100) AS quantiles
    FROM per_patient_peak
  )
);