WITH sodium_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%sodium%'
    AND LOWER(fluid) = 'serum'
),
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
index_icu_stays AS (
  -- For each hospital admission, get the first ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
  WHERE icu.rn = 1
),
first_sodium AS (
  -- For each index ICU stay, get the first sodium value after ICU admission
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.stay_id,
    MIN(lab.charttime) AS first_sodium_time
  FROM index_icu_stays idx
  JOIN male_patients mp ON idx.subject_id = mp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON idx.subject_id = lab.subject_id
    AND idx.hadm_id = lab.hadm_id
    AND lab.valuenum IS NOT NULL
    AND lab.charttime >= idx.intime
  JOIN sodium_itemids si ON lab.itemid = si.itemid
  GROUP BY idx.subject_id, idx.hadm_id, idx.stay_id
),
first_sodium_values AS (
  -- Get the sodium value at the first sodium time
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    lab.valuenum AS sodium_value
  FROM first_sodium fs
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON fs.subject_id = lab.subject_id
    AND fs.hadm_id = lab.hadm_id
    AND lab.valuenum IS NOT NULL
    AND lab.charttime = fs.first_sodium_time
  JOIN sodium_itemids si ON lab.itemid = si.itemid
)
SELECT
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS sodium_25th_percentile,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] AS sodium_75th_percentile,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] - APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS sodium_IQR
FROM first_sodium_values;