WITH hr_items AS (
  -- Identify heart rate itemids in the ICU d_items catalog
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
filtered_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN hr_items hi ON ce.itemid = hi.itemid
  -- Link to ICU stay to ensure within ICU period
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON ce.subject_id = ic.subject_id
   AND ce.hadm_id = ic.hadm_id
  -- Demographics and admission info from the hosp module
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ce.subject_id = a.subject_id
   AND ce.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    -- Age at admission: anchor_age + (admit_year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
    -- HR measurement occurred during ICU stay
    AND ce.charttime >= ic.intime
    AND ce.charttime <= ic.outtime
)
SELECT
  MIN(first_hr) AS min_first_hr
FROM (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum AS first_hr,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
  FROM filtered_events
) AS ranked
WHERE rn = 1;