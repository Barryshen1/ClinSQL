WITH female_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
hs_tnt_items AS (
  SELECT
    hi.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems` hi
  WHERE
    (
      LOWER(hi.label) LIKE '%troponin t%'
      AND LOWER(hi.label) LIKE '%high sensitivity%'
    )
    OR hi.loinc_code = '6598-7'
),
first_hs_tnt AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    le.valuenum AS tnt_val
  FROM
    female_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      USING (subject_id, hadm_id)
    JOIN hs_tnt_items hi
      USING (itemid)
  WHERE
    le.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY fa.hadm_id ORDER BY le.charttime ASC) = 1
),
filtered_initial_tnt AS (
  SELECT
    tnt_val
  FROM
    first_hs_tnt
  WHERE
    tnt_val > 0.014
),
tnt_stats AS (
  SELECT
    APPROX_QUANTILES(tnt_val, 100) AS quantiles,
    MIN(tnt_val) AS min_val,
    MAX(tnt_val) AS max_val
  FROM
    filtered_initial_tnt
)
SELECT
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS p50,
  quantiles[OFFSET(75)] AS p75,
  min_val,
  max_val
FROM
  tnt_stats;