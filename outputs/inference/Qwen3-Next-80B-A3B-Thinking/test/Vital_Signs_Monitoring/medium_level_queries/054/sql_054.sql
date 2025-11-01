WITH target_icustays AS (
  SELECT
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND EXTRACT(YEAR FROM icustays.intime) - (patients.anchor_year - patients.anchor_age) BETWEEN 87 AND 97
),
sbp_averages AS (
  SELECT
    ti.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM target_icustays ti
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ti.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220050  -- Systolic BP
    AND ce.charttime BETWEEN ti.intime AND ti.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY ti.stay_id
)
SELECT
  SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM sbp_averages;