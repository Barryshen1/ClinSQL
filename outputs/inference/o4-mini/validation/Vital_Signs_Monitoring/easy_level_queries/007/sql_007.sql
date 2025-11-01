WITH rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
),
first_stay AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    i.stay_id,
    ROW_NUMBER() OVER (
      PARTITION BY c.subject_id
      ORDER BY i.intime
    ) AS rn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id
   AND c.hadm_id    = i.hadm_id
),
rr_first AS (
  SELECT
    ce.subject_id,
    ce.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY ce.subject_id
      ORDER BY ce.charttime
    ) AS rn2
  FROM first_stay fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = fs.subject_id
   AND ce.hadm_id    = fs.hadm_id
   AND ce.stay_id    = fs.stay_id
  JOIN rr_items ri
    ON ce.itemid = ri.itemid
  WHERE
    fs.rn = 1
    AND ce.valuenum IS NOT NULL
)
SELECT
  STDDEV_SAMP(valuenum) AS sd_first_respiratory_rate
FROM rr_first
WHERE rn2 = 1;