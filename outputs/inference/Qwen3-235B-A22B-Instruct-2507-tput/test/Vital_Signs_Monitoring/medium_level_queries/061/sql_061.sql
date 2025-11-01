WITH patient_admission AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
icu_stays_with_age AS (
  SELECT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    pa.age_at_admission,
    pa.gender
  FROM
    `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN
    patient_admission pa
  ON
    i.subject_id = pa.subject_id
  WHERE
    pa.gender = 'M'
    AND pa.age_at_admission >= 38
    AND pa.age_at_admission <= 48
),
map_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) = 'mean blood pressure'
),
avg_map_per_stay AS (
  SELECT
    i.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM
    icu_stays_with_age i
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON
    i.stay_id = ce.stay_id
  INNER JOIN
    map_item m
  ON
    ce.itemid = m.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
  GROUP BY
    i.stay_id
)
SELECT
  AVG(CASE WHEN avg_map <= 60 THEN 1.0 ELSE 0.0 END) AS proportion_le_60
FROM
  avg_map_per_stay;