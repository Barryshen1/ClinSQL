WITH male_age_cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
),
nippv_stays AS (
  SELECT DISTINCT proc.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` proc
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%cpap%'
     OR LOWER(di.label) LIKE '%bipap%'
),
max_dbp_per_stay AS (
  SELECT ce.stay_id,
         MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%diastolic%'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
cohort_max_dbp AS (
  SELECT m.stay_id, m.max_dbp
  FROM max_dbp_per_stay m
  JOIN male_age_cohort c
    ON m.stay_id = c.stay_id
  JOIN nippv_stays n
    ON m.stay_id = n.stay_id
)
SELECT
  APPROX_QUANTILES(max_dbp, 4)[OFFSET(1)] AS p25_max_dbp
FROM cohort_max_dbp;