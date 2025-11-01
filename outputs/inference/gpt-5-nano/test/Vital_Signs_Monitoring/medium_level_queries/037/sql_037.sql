WITH icu_cohort AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = ic.subject_id
  WHERE
    LOWER(p.gender) IN ('f', 'female')
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- approximate age at ICU start
    AND (p.anchor_age + (EXTRACT(YEAR FROM ic.intime) - p.anchor_year)) BETWEEN 88 AND 98
)

SELECT
  (CASE
     WHEN quantiles IS NULL THEN NULL
     ELSE quantiles[OFFSET(50)]
   END) AS median_gcs_total
FROM (
  SELECT APPROX_QUANTILES(ce.valuenum, 100) AS quantiles
  FROM icu_cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%glasgow%'
    AND (LOWER(di.label) LIKE '%total%' OR LOWER(di.label) LIKE '%gcs%')
    AND ce.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(ce.charttime, c.intime, DAY) >= 1
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS die
        ON ie.itemid = die.itemid
      WHERE ie.subject_id = c.subject_id
        AND ie.hadm_id = c.hadm_id
        AND ie.stay_id = c.stay_id
        AND LOWER(die.label) LIKE '%high flow%' AND LOWER(die.label) LIKE '%nasal%'
    )
) AS t;