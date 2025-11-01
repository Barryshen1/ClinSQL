WITH resp_rate_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
),

female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),

icu_stays AS (
  SELECT stay_id, subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (SELECT subject_id FROM female_patients)
),

max_resp_rate_per_stay AS (
  SELECT
    s.subject_id,
    s.stay_id,
    MAX(c.valuenum) AS max_resp_rate
  FROM icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id AND s.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM resp_rate_itemids)
    AND c.valuenum IS NOT NULL
  GROUP BY s.subject_id, s.stay_id
),

max_resp_rate_per_patient AS (
  SELECT
    subject_id,
    MAX(max_resp_rate) AS patient_max_resp_rate
  FROM max_resp_rate_per_stay
  GROUP BY subject_id
)

SELECT
  STDDEV(patient_max_resp_rate) AS sd_max_resp_rate
FROM max_resp_rate_per_patient
WHERE patient_max_resp_rate IS NOT NULL;