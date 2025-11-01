WITH heart_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
),

female_icu_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
)

, first_heart_rate AS (
  SELECT
    fip.subject_id,
    fip.hadm_id,
    fip.stay_id,
    MIN(ce.charttime) AS first_hr_time
  FROM female_icu_patients fip
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fip.subject_id = ce.subject_id
    AND fip.hadm_id = ce.hadm_id
    AND fip.stay_id = ce.stay_id
  JOIN heart_rate_itemid hri
    ON ce.itemid = hri.itemid
  WHERE
    ce.charttime BETWEEN fip.intime AND fip.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY fip.subject_id, fip.hadm_id, fip.stay_id
)

, first_heart_rate_value AS (
  SELECT
    fhr.subject_id,
    fhr.hadm_id,
    fhr.stay_id,
    ce.valuenum AS first_heart_rate
  FROM first_heart_rate fhr
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fhr.subject_id = ce.subject_id
    AND fhr.hadm_id = ce.hadm_id
    AND fhr.stay_id = ce.stay_id
    AND fhr.first_hr_time = ce.charttime
  JOIN heart_rate_itemid hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
)

SELECT MIN(first_heart_rate) AS min_first_recorded_heart_rate
FROM first_heart_rate_value;