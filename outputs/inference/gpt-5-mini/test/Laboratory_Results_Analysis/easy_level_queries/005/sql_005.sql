WITH sodium_items AS (
  -- identify sodium-related lab itemids by label (loinc_code not referenced because it may not exist in this snapshot)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%sodium%'
), first_sodium_candidates AS (
  -- join icu stays to lab events during the ICU stay for male patients
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    le.labevent_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = icu.subject_id
   AND le.hadm_id = icu.hadm_id
  JOIN sodium_items si
    ON le.itemid = si.itemid
  WHERE p.gender = 'M'
    AND le.charttime BETWEEN icu.intime AND icu.outtime
    AND le.valuenum IS NOT NULL
), first_sodium_per_stay AS (
  -- pick the earliest sodium lab per ICU stay (break ties by labevent_id)
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    labevent_id,
    charttime,
    valuenum
  FROM (
    SELECT
      fsc.*,
      ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime, labevent_id) AS rn
    FROM first_sodium_candidates fsc
  )
  WHERE rn = 1
), quantiles AS (
  -- compute approximate centiles across index sodium values
  SELECT
    APPROX_QUANTILES(valuenum, 100) AS centiles,
    COUNT(*) AS n_stays
  FROM first_sodium_per_stay
)
SELECT
  centiles[OFFSET(25)] AS p25_sodium,
  centiles[OFFSET(75)] AS p75_sodium,
  centiles[OFFSET(75)] - centiles[OFFSET(25)] AS iqr_sodium,
  n_stays AS number_of_male_icu_stays_with_index_sodium
FROM quantiles;