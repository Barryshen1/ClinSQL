WITH rr_mean_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON icu.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items AS d
    ON ce.itemid = d.itemid
  WHERE
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 39 AND 49
    AND d.label LIKE '%Respiratory rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
)
SELECT
  PERCENTILE_CONT(mean_rr, 0.75) OVER() AS percentile_75_mean_rr
FROM
  rr_mean_per_stay
LIMIT 1;