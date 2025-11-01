WITH
-- ICU d_items potassium candidates (exclude urine)
icu_pot_items AS (
  SELECT itemid, LOWER(label) AS label, LOWER(COALESCE(unitname, '')) AS unitname
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%potassium%'
    AND NOT LOWER(label) LIKE '%urine%'
),

-- HOSP d_labitems potassium candidates (exclude urine)
hosp_pot_items AS (
  SELECT itemid, LOWER(label) AS label, LOWER(COALESCE(fluid, '')) AS fluid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
    AND NOT LOWER(label) LIKE '%urine%'
),

-- Potassium measurements within ICU stays from chartevents and labevents
potassium_measurements AS (

  -- ICU bedside measurements
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS val,
    LOWER(COALESCE(ce.valueuom, di.unitname)) AS uom,
    'chartevent' AS source
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_pot_items di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON ce.subject_id = ic.subject_id
   AND ce.hadm_id = ic.hadm_id
   AND ce.charttime BETWEEN ic.intime AND ic.outtime
  WHERE ce.valuenum IS NOT NULL
    -- accept common potassium units or missing unit
    AND (
      LOWER(ce.valueuom) IN ('meq/l','mmol/l')
      OR ce.valueuom IS NULL
      OR di.unitname IN ('meq/l','mmol/l')
    )

  UNION ALL

  -- Hospital lab measurements (link to icu stays by hadm_id and time)
  SELECT
    le.subject_id,
    le.hadm_id,
    ic.stay_id,
    le.charttime,
    le.valuenum AS val,
    LOWER(COALESCE(le.valueuom, '')) AS uom,
    'labevent' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hosp_pot_items dl
    ON le.itemid = dl.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON le.subject_id = ic.subject_id
   AND le.hadm_id = ic.hadm_id
   AND le.charttime BETWEEN ic.intime AND ic.outtime
  WHERE le.valuenum IS NOT NULL
    -- accept common potassium units or missing unit
    AND (
      LOWER(le.valueuom) IN ('meq/l','mmol/l')
      OR le.valueuom IS NULL
    )
),

-- Peak potassium per ICU stay
peaks AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(val) AS peak_k_mEq_per_L
  FROM potassium_measurements
  GROUP BY subject_id, hadm_id, stay_id
)

-- Final: standard deviation across stays for 56-year-old males
SELECT
  STDDEV_POP(p.peak_k_mEq_per_L) AS sd_peak_potassium_mEq_per_L,
  COUNT(*) AS n_icustays
FROM peaks p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND pt.anchor_age = 56;