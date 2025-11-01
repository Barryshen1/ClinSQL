WITH cohort AS (
  -- Select male ICU stays for patients aged 38-48
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
),
map_items AS (
  -- Find itemids for MAP
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
),
map_per_stay AS (
  -- Compute per-stay average MAP
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
    JOIN map_items mi
      ON ce.itemid = mi.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- exclude negative/zero values
  GROUP BY
    c.stay_id
)
SELECT
  SAFE_DIVIDE(
    COUNTIF(avg_map <= 60),
    COUNT(*)
  ) AS percentile_rank_le_60mmHg
FROM
  map_per_stay
WHERE
  avg_map IS NOT NULL
;