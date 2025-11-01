WITH
  hs_tnt_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%hs-TnT%'
  ),
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 59 AND 69
  ),
  hs_tnt_labs AS (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum,
      le.valueuom
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN hs_tnt_itemids d ON le.itemid = d.itemid
    INNER JOIN eligible_patients p ON le.subject_id = p.subject_id
    WHERE le.valuenum > 0.014  -- only measurements above the threshold
  ),
  first_hs_tnt_per_admission AS (
    SELECT
      hadm_id,
      valuenum AS initial_hs_tnt
    FROM (
      SELECT
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
      FROM hs_tnt_labs
    ) ranked
    WHERE rn = 1
  ),
  stats AS (
    SELECT
      APPROX_QUANTILES(initial_hs_tnt, 100) AS quantiles,
      MIN(initial_hs_tnt) AS min_value,
      MAX(initial_hs_tnt) AS max_value
    FROM first_hs_tnt_per_admission
  )
SELECT
  quantiles[SAFE_OFFSET(25)] AS percentile_25,
  quantiles[SAFE_OFFSET(50)] AS percentile_50,
  quantiles[SAFE_OFFSET(75)] AS percentile_75,
  min_value,
  max_value
FROM stats;