WITH resp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

female_admissions AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
)

, first_resp_rate AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    MIN(c.charttime) AS first_charttime
  FROM female_admissions fa
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON fa.subject_id = c.subject_id
    AND fa.hadm_id = c.hadm_id
  JOIN resp_itemids ri
    ON c.itemid = ri.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.charttime >= fa.admittime
    AND c.charttime <= TIMESTAMP_ADD(fa.admittime, INTERVAL 6 HOUR)
  GROUP BY fa.subject_id, fa.hadm_id
)

SELECT
  STDDEV_SAMP(c.valuenum) AS sd_first_resp_rate
FROM first_resp_rate fr
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON fr.subject_id = c.subject_id
  AND fr.hadm_id = c.hadm_id
  AND fr.first_charttime = c.charttime
JOIN resp_itemids ri
  ON c.itemid = ri.itemid
WHERE c.valuenum IS NOT NULL;