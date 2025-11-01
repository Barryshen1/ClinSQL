WITH first_trop AS (
  SELECT
    l.subject_id,
    MIN(l.charttime) AS first_charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
  GROUP BY
    l.subject_id
),

trop_values AS (
  SELECT
    l.subject_id,
    l.valuenum AS troponin_t
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
  ON
    l.itemid = d.itemid
  JOIN
    first_trop ft
  ON
    l.subject_id = ft.subject_id
    AND l.charttime = ft.first_charttime
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.014
),

patient_los AS (
  SELECT
    subject_id,
    AVG(los) AS mean_los
  FROM
    physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY
    subject_id
)

SELECT
  COUNT(DISTINCT p.subject_id) AS N,
  AVG(p.anchor_age) AS mean_age,
  AVG(pl.mean_los) AS mean_los,
  AVG(t.troponin_t) AS mean_trop,
  MIN(t.troponin_t) AS min_trop,
  MAX(t.troponin_t) AS max_trop
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  trop_values t
ON
  p.subject_id = t.subject_id
JOIN
  patient_los pl
ON
  p.subject_id = pl.subject_id
WHERE
  p.anchor_age BETWEEN 83 AND 93
  AND p.gender = 'M';