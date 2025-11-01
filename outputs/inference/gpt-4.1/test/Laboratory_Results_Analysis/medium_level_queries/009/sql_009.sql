WITH hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%' AND LOWER(label) LIKE '%t%'
    AND (LOWER(label) LIKE '%high%' OR LOWER(label) LIKE '%hs%')
    AND LOWER(category) LIKE '%chemistry%'
),
female_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
first_hs_tnt AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    l.charttime,
    l.valuenum
  FROM female_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON fa.subject_id = l.subject_id AND fa.hadm_id = l.hadm_id
  JOIN hs_tnt_items hsi
    ON l.itemid = hsi.itemid
  WHERE l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
)
, first_hs_tnt_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM first_hs_tnt
  GROUP BY subject_id, hadm_id
)
, initial_hs_tnt AS (
  SELECT
    fhta.subject_id,
    fhta.hadm_id,
    fhta.first_charttime,
    fht.valuenum AS initial_hs_tnt
  FROM first_hs_tnt_per_admission fhta
  JOIN first_hs_tnt fht
    ON fhta.subject_id = fht.subject_id
    AND fhta.hadm_id = fht.hadm_id
    AND fhta.first_charttime = fht.charttime
  WHERE fht.valuenum > 0.014
)
SELECT
  MIN(initial_hs_tnt) AS min_initial_hs_tnt,
  MAX(initial_hs_tnt) AS max_initial_hs_tnt,
  APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(initial_hs_tnt, 4)[OFFSET(3)] AS percentile_75
FROM initial_hs_tnt
;