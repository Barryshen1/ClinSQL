WITH cohort_map AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    physionet-data.mimiciv_3_1_hosp.patients pat
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON pat.subject_id = icu.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON icu.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
    AND di.label = 'MAP'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    icu.stay_id
),
percentile_ranks AS (
  SELECT
    mean_map,
    PERCENT_RANK() OVER (ORDER BY mean_map) AS percentile_rank
  FROM
    cohort_map
)
SELECT
  MAX(CASE WHEN mean_map = 75 THEN percentile_rank END) AS percentile_of_75_mmhg
FROM
  percentile_ranks;