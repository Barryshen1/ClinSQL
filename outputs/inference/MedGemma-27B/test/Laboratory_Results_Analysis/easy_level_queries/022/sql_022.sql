WITH PeakpH AS (
  SELECT
    p.subject_id,
    MAX(ce.valuenum) AS max_ph
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON ce.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS is_ ON ce.hadm_id = is_.hadm_id
  WHERE
    di.label = 'pH'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 6.0 AND 8.0
    AND p.gender = 'M'
    AND p.anchor_age = 63
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, max_ph) AS iqr_25,
  PERCENTILE_CONT(0.75, max_ph) AS iqr_75
FROM
  PeakpH;