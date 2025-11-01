WITH peak_pH AS (
  SELECT
    p.subject_id,
    MAX(c.valuenum) AS peak_pH
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE
    p.gender = 'M'
    AND c.itemid = 50820
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY peak_pH) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY peak_pH) AS iqr
FROM peak_pH;