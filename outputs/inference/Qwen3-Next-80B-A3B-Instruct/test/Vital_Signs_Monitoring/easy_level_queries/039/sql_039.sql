WITH first_respiratory_rate AS (
  SELECT
    i.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d.label = 'Respiratory Rate'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= i.intime
    AND c.charttime <= i.outtime
)
SELECT
  PERCENTILE_CONT(valuenum, 0.25) OVER () AS p25_respiratory_rate
FROM
  first_respiratory_rate
WHERE
  rn = 1
LIMIT 1;