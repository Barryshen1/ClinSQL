WITH systolic_items AS (
  -- Identify itemids that likely correspond to systolic blood pressure
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE REGEXP_CONTAINS(LOWER(label), r'systolic')
     OR (abbreviation IS NOT NULL AND REGEXP_CONTAINS(LOWER(abbreviation), r'systolic|sbp|sys'))
),
female_elderly_stays AS (
  -- ICU stays for female patients aged 87-97 (anchor_age)
  SELECT icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 87 AND 97
    AND (UPPER(p.gender) IN ('F', 'FEMALE'))
),
sbp_first24_values AS (
  -- All systolic BP valuenum measurements within first 24 hours of each stay
  SELECT sfs.stay_id,
         ce.valuenum
  FROM female_elderly_stays sfs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = sfs.stay_id
   AND ce.charttime BETWEEN sfs.intime AND TIMESTAMP_ADD(sfs.intime, INTERVAL 24 HOUR)
  JOIN systolic_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
),
per_stay_avg_sbp AS (
  -- Per-stay average systolic BP in the first 24 hours
  SELECT stay_id,
         AVG(valuenum) AS avg_sbp
  FROM sbp_first24_values
  GROUP BY stay_id
)
-- Final percentile calculation: percent of stays with avg_sbp <= 150 mmHg
SELECT
  COUNT(*) AS n_stays,
  SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END) AS n_leq_150,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_leq_150
FROM per_stay_avg_sbp;