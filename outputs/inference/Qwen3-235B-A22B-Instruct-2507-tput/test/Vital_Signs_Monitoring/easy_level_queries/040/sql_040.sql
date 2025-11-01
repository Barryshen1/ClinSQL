WITH map_first AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS first_map
  FROM (
    SELECT
      ce.stay_id,
      ce.valuenum,
      ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
      ON ce.itemid = di.itemid
    WHERE UPPER(di.label) = 'MAP'
      AND ce.valuenum IS NOT NULL
  ) ce
  WHERE ce.rn = 1
),
patient_icu_age AS (
  SELECT
    p.subject_id,
    i.stay_id,
    p.gender,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    (DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
)
SELECT
  ROUND(STDDEV(mf.first_map), 2) AS map_std_dev
FROM map_first mf
INNER JOIN patient_icu_age pia
  ON mf.stay_id = pia.stay_id
WHERE pia.gender = 'M'
  AND pia.age_at_admission >= 55
  AND pia.age_at_admission <= 65;