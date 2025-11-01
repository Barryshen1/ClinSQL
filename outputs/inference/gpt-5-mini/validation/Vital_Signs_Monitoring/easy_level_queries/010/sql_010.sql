WITH per_stay_max AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(di.label) LIKE '%diastolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 250
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
),

sorted AS (
  SELECT
    max_dbp,
    ROW_NUMBER() OVER (ORDER BY max_dbp) AS rn
  FROM per_stay_max
),

counts AS (
  SELECT COUNT(*) AS cnt FROM per_stay_max
)

SELECT
  CASE
    WHEN c.cnt = 0 THEN NULL
    WHEN MOD(c.cnt, 2) = 1 THEN
      -- odd: take the middle value
      (SELECT CAST(max_dbp AS FLOAT64) FROM sorted WHERE rn = (c.cnt + 1) / 2 LIMIT 1)
    ELSE
      -- even: average the two middle values
      (SELECT AVG(max_dbp) FROM sorted WHERE rn IN (c.cnt / 2, c.cnt / 2 + 1))
  END AS median_per_stay_max_dbp,
  c.cnt AS num_stays_in_cohort
FROM counts c
LIMIT 1;