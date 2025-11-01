WITH cohort AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    ie.intime,
    ie.outtime,
    pat.gender,
    pat.anchor_age + EXTRACT(YEAR FROM ie.intime) - pat.anchor_year AS age
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
      ON ie.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
      ON ie.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM ie.intime) - pat.anchor_year) BETWEEN 38 AND 48
),
systolic_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) = 'systolic blood pressure'
),
stay_systolic_avg AS (
  SELECT
    co.stay_id,
    AVG(ce.valuenum) AS avg_systolic
  FROM
    cohort co
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
      ON co.stay_id = ce.stay_id
  JOIN
    systolic_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.charttime >= co.intime
    AND ce.charttime <= co.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY
    co.stay_id
),
distribution_with_target AS (
  SELECT avg_systolic AS value FROM stay_systolic_avg
  UNION ALL
  SELECT 120.0 AS value
),
percentile_ranking AS (
  SELECT
    value,
    PERCENT_RANK() OVER (ORDER BY value) * 100 AS percentile_rank
  FROM
    distribution_with_target
)
SELECT
  percentile_rank
FROM
  percentile_ranking
WHERE
  value = 120.0
LIMIT 1;