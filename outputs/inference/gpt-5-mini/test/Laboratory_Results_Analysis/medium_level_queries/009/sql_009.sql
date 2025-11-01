WITH hs_tn_items AS (
  -- candidate troponin T items (labels containing "troponin t")
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%hs troponin t%'
     OR LOWER(label) LIKE '%high sensitivity troponin t%'
),

tnt_per_admission AS (
  -- all troponin T lab rows that fall within the hospital admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hs_tn_items hti
    ON le.itemid = hti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
   AND le.subject_id = a.subject_id
  WHERE le.valuenum IS NOT NULL
    -- prefer measurements in ng (ng/mL). Allow rows with missing unit too.
    AND (LOWER(COALESCE(le.valueuom, '')) LIKE '%ng%' OR le.valueuom IS NULL)
    -- restrict lab to occur during the admission
    AND le.charttime BETWEEN a.admittime AND a.dischtime
),

first_tnt_per_admission AS (
  -- take the earliest troponin per admission (initial hs-TnT)
  SELECT
    subject_id,
    hadm_id,
    valuenum AS initial_tnt,
    charttime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM tnt_per_admission
)

SELECT
  MIN(initial_tnt) AS initial_tnt_min,
  MAX(initial_tnt) AS initial_tnt_max,
  -- APPROX_QUANTILES(..., 100) returns 101 values (0..100 percentiles)
  -- OFFSET(25) ~ 25th percentile, OFFSET(50) ~ median, OFFSET(75) ~ 75th percentile
  approx_quantiles(initial_tnt, 100)[OFFSET(25)] AS initial_tnt_p25,
  approx_quantiles(initial_tnt, 100)[OFFSET(50)] AS initial_tnt_p50,
  approx_quantiles(initial_tnt, 100)[OFFSET(75)] AS initial_tnt_p75,
  COUNT(1) AS n_admissions
FROM (
  -- join to patients & admissions to get age/gender and filter initial tnt > 0.014
  SELECT fta.hadm_id, fta.subject_id, fta.initial_tnt
  FROM first_tnt_per_admission fta
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fta.hadm_id = a.hadm_id
   AND fta.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fta.subject_id = p.subject_id
  WHERE fta.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND fta.initial_tnt > 0.014
);