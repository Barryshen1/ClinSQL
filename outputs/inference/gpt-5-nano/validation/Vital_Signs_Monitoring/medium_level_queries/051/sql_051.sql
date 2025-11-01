WITH eligible AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE LOWER(pat.gender) = 'male'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 55 AND 65
),

hr_per_stay AS (
  SELECT
    e.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MAX(ce.valuenum) AS max_hr_per_stay
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON e.subject_id = icu.subject_id
   AND e.hadm_id = icu.hadm_id
   AND e.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY e.subject_id, icu.hadm_id, icu.stay_id
),

hr_per_patient AS (
  SELECT
    subject_id,
    MAX(max_hr_per_stay) AS max_hr
  FROM hr_per_stay
  GROUP BY subject_id
)

SELECT
  q[OFFSET(1)] AS q1,
  q[OFFSET(3)] AS q3,
  (q[OFFSET(3)] - q[OFFSET(1)]) AS iqr
FROM (
  SELECT APPROX_QUANTILES(CAST(max_hr AS FLOAT64), 4) AS q
  FROM hr_per_patient
);