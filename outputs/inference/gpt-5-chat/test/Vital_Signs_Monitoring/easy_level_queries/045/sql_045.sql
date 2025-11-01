WITH rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
male_icu_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_rr AS (
  SELECT
    cep.subject_id,
    cep.valuenum,
    cep.charttime,
    ROW_NUMBER() OVER (PARTITION BY cep.subject_id ORDER BY cep.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` cep
  JOIN male_icu_patients m
    ON cep.subject_id = m.subject_id
  JOIN rr_items ri
    ON cep.itemid = ri.itemid
  WHERE cep.valuenum IS NOT NULL
)
SELECT
  STDDEV_SAMP(valuenum) AS sd_first_rr
FROM first_rr
WHERE rn = 1;