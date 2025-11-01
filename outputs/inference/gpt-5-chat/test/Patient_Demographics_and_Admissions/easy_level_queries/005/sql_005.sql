WITH female_elderly AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),
dialysis_stays AS (
  SELECT DISTINCT pe.subject_id, pe.hadm_id, pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
),
first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  WHERE icu.subject_id IN (SELECT subject_id FROM female_elderly)
),
cohort AS (
  SELECT fi.los
  FROM first_icu fi
  JOIN dialysis_stays ds
    ON fi.subject_id = ds.subject_id
   AND fi.stay_id = ds.stay_id
  WHERE fi.rn = 1
)
SELECT
  PERCENTILE_CONT(los, 0.75) OVER() -
  PERCENTILE_CONT(los, 0.25) OVER() AS iqr_days
FROM cohort
LIMIT 1;