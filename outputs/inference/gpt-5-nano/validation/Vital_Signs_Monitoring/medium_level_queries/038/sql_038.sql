WITH
-- Step 1: define the male 66–76 cohort from hosp patients
cohort_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE LOWER(p.gender) = 'male'
    AND p.anchor_age BETWEEN 66 AND 76
),

-- Step 2: identify ICU stays with invasive ventilation (intubation)
ventilated_icustays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN cohort_patients AS cp
    ON cp.subject_id = i.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
    WHERE pe.subject_id = i.subject_id
      AND pe.hadm_id = i.hadm_id
      AND (
        LOWER(di.label) LIKE '%intubation%' OR
        LOWER(di.label) LIKE '%endotracheal%' OR
        LOWER(di.label) LIKE '%tracheal%ventilation%'
      )
  )
),

-- Step 3: SBP measurements within first 6 hours of ICU intime
sbp_measurements AS (
  SELECT
    vi.subject_id,
    vi.hadm_id,
    vi.stay_id,
    ce.charttime,
    ce.valuenum
  FROM ventilated_icustays AS vi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = vi.subject_id
   AND ce.hadm_id = vi.hadm_id
   AND ce.stay_id = vi.stay_id
   AND ce.charttime >= vi.intime
   AND ce.charttime < TIMESTAMP_ADD(vi.intime, INTERVAL 6 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- identify systolic blood pressure entries
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%blood%'
)

-- Step 4: compute IQR from SBP values
SELECT
  quant[OFFSET(1)] AS q1,
  quant[OFFSET(3)] AS q3,
  quant[OFFSET(3)] - quant[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quant
  FROM sbp_measurements
) AS t;