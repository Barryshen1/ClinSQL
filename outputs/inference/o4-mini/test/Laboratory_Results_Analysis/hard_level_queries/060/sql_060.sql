WITH cardiac_arrest_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%cardiac arrest%'
),
female_52_62 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
admissions_with_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN cardiac_arrest_codes c
          ON d.icd_code = c.icd_code
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id = a.hadm_id
      )
      THEN 'cardiac_arrest'
      ELSE 'general'
    END AS cohort
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_52_62 f
    ON a.subject_id = f.subject_id
),
first_icu_stay AS (
  -- take the first ICU stay per admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN (
    SELECT subject_id, hadm_id, MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id, hadm_id
  ) firsts
    ON i.subject_id = firsts.subject_id
   AND i.hadm_id    = firsts.hadm_id
   AND i.intime     = firsts.first_intime
),
instability_scores AS (
  -- assume itemid = 220045 corresponds to the “instability score”
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS instability_score,
    TIMESTAMP_DIFF(ce.charttime, fs.intime, HOUR) AS hours_since_icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN first_icu_stay fs
    ON ce.subject_id = fs.subject_id
   AND ce.hadm_id    = fs.hadm_id
   AND ce.stay_id    = fs.stay_id
  WHERE ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(ce.charttime, fs.intime, HOUR) BETWEEN 0 AND 48
),
cohort_scores AS (
  SELECT
    a.cohort,
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    fs.los,
    a.hospital_expire_flag
  FROM instability_scores s
  JOIN first_icu_stay fs
    ON s.subject_id = fs.subject_id
   AND s.hadm_id    = fs.hadm_id
   AND s.stay_id    = fs.stay_id
  JOIN admissions_with_cohort a
    ON s.subject_id = a.subject_id
   AND s.hadm_id    = a.hadm_id
)
SELECT
  cohort,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS Q1_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median_instability_score,
  COUNT(DISTINCT CONCAT(subject_id, '-', hadm_id)) AS n_patients,
  AVG(los) AS avg_icu_los_days,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM cohort_scores
GROUP BY cohort
ORDER BY cohort;