WITH female_patients_44_54 AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),

first_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

heart_rate_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label LIKE '%Heart Rate%'
    AND linksto = 'chartevents'
),

heart_rate_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    heart_rate_itemids hri ON ce.itemid = hri.itemid
  JOIN
    first_icu_stay fis ON ce.subject_id = fis.subject_id AND ce.stay_id = fis.stay_id
  WHERE
    fis.stay_rank = 1  -- First ICU stay
    AND ce.charttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
)

SELECT
  fp.subject_id,
  fp.gender,
  fp.anchor_age,
  MIN(hrm.heart_rate) AS min_heart_rate_first_24h
FROM
  female_patients_44_54 fp
JOIN
  heart_rate_measurements hrm ON fp.subject_id = hrm.subject_id
GROUP BY
  fp.subject_id, fp.gender, fp.anchor_age
ORDER BY
  min_heart_rate_first_24h ASC;