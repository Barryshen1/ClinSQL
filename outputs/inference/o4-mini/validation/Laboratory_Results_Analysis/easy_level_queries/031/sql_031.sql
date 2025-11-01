WITH male_icu_admissions AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ic.subject_id = a.subject_id
     AND ic.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
),
potassium_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%potassium%'
    AND LOWER(category) LIKE '%chemistry%'
    AND LOWER(fluid) IN ('blood', 'serum', 'plasma')
)

SELECT
  -- Use APPROX_QUANTILES and take the 75th percentile (offset 75 of 0..100)
  (APPROX_QUANTILES(le.valuenum, 100))[OFFSET(75)] AS potassium_75th_percentile
FROM
  male_icu_admissions mia
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mia.subject_id = le.subject_id
   AND mia.hadm_id = le.hadm_id
  JOIN potassium_items ki
    ON le.itemid = ki.itemid
WHERE
  le.valuenum IS NOT NULL
  AND DATE(le.charttime) = DATE(mia.dischtime);