WITH itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%mean arterial pressure%' OR abbreviation = 'MAP' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%resp rate%' OR abbreviation = 'Resp Rate' THEN itemid END) AS rr_itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
),

-- Step 1: Heart failure ICD codes
hf_icds AS (
  SELECT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- Step 2: Cohort selection (male, 45-55, heart failure, ICU stays)
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag,
    pat.dod
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm ON icu.hadm_id = adm.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag ON icu.hadm_id = diag.hadm_id
  JOIN hf_icds ON diag.icd_code = hf_icds.icd_code AND diag.icd_version = hf_icds.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
),

-- Step 3: All ICU stays (for comparison)
all_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag,
    pat.dod
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm ON icu.hadm_id = adm.hadm_id
),

-- Step 4: Instability events for cohort
cohort_events AS (
  SELECT
    c.stay_id,
    SUM(CASE WHEN ce.itemid = i.hr_itemid AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_events,
    SUM(CASE WHEN ce.itemid = i.map_itemid AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_events,
    SUM(CASE WHEN ce.itemid = i.rr_itemid AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_events,
    SUM(
      CASE
        WHEN (ce.itemid = i.hr_itemid AND ce.valuenum > 100)
          OR (ce.itemid = i.map_itemid AND ce.valuenum < 65)
          OR (ce.itemid = i.rr_itemid AND ce.valuenum > 20)
        THEN 1 ELSE 0
      END
    ) AS composite_score
  FROM cohort c
  CROSS JOIN itemids i
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (i.hr_itemid, i.map_itemid, i.rr_itemid)
  GROUP BY c.stay_id
),

-- Step 5: Instability events for all ICU stays
all_icu_events AS (
  SELECT
    a.stay_id,
    SUM(CASE WHEN ce.itemid = i.hr_itemid AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_events,
    SUM(CASE WHEN ce.itemid = i.map_itemid AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_events,
    SUM(CASE WHEN ce.itemid = i.rr_itemid AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_events,
    SUM(
      CASE
        WHEN (ce.itemid = i.hr_itemid AND ce.valuenum > 100)
          OR (ce.itemid = i.map_itemid AND ce.valuenum < 65)
          OR (ce.itemid = i.rr_itemid AND ce.valuenum > 20)
        THEN 1 ELSE 0
      END
    ) AS composite_score
  FROM all_icu a
  CROSS JOIN itemids i
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON a.stay_id = ce.stay_id
    AND ce.charttime BETWEEN a.intime AND TIMESTAMP_ADD(a.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (i.hr_itemid, i.map_itemid, i.rr_itemid)
  GROUP BY a.stay_id
),

-- Step 6: 99th percentile of composite score for cohort
cohort_percentile AS (
  SELECT
    PERCENTILE_CONT(composite_score, 0.99) AS composite_score_99th
  FROM cohort_events
),

-- Step 7: Most unstable quartile (top 25%) using NTILE
cohort_quartile AS (
  SELECT
    ce.*,
    NTILE(4) OVER (ORDER BY composite_score DESC) AS quartile
  FROM cohort_events ce
),
most_unstable_cohort AS (
  SELECT *
  FROM cohort_quartile
  WHERE quartile = 1
),

all_icu_quartile AS (
  SELECT
    ae.*,
    NTILE(4) OVER (ORDER BY composite_score DESC) AS quartile
  FROM all_icu_events ae
),
most_unstable_icu AS (
  SELECT *
  FROM all_icu_quartile
  WHERE quartile = 1
),

-- Step 8: Add LOS and mortality for cohort
cohort_metrics AS (
  SELECT
    ce.stay_id,
    ce.tachycardia_events,
    ce.map_low_events,
    ce.tachypnea_events,
    ce.composite_score,
    c.los,
    c.hospital_expire_flag,
    c.dod
  FROM cohort_events ce
  JOIN cohort c ON ce.stay_id = c.stay_id
),

most_unstable_cohort_metrics AS (
  SELECT
    muc.stay_id,
    muc.tachycardia_events,
    muc.map_low_events,
    muc.tachypnea_events,
    muc.composite_score,
    c.los,
    c.hospital_expire_flag,
    c.dod
  FROM most_unstable_cohort muc
  JOIN cohort c ON muc.stay_id = c.stay_id
),

all_icu_metrics AS (
  SELECT
    ae.stay_id,
    ae.tachycardia_events,
    ae.map_low_events,
    ae.tachypnea_events,
    ae.composite_score,
    a.los,
    a.hospital_expire_flag,
    a.dod
  FROM all_icu_events ae
  JOIN all_icu a ON ae.stay_id = a.stay_id
),

most_unstable_icu_metrics AS (
  SELECT
    mui.stay_id,
    mui.tachycardia_events,
    mui.map_low_events,
    mui.tachypnea_events,
    mui.composite_score,
    a.los,
    a.hospital_expire_flag,
    a.dod
  FROM most_unstable_icu mui
  JOIN all_icu a ON mui.stay_id = a.stay_id
)

-- Final output
SELECT
  'Cohort (Male 45-55 w/ HF)' AS group,
  (SELECT composite_score_99th FROM cohort_percentile) AS composite_score_99th,
  -- Most unstable quartile metrics
  (SELECT AVG(tachycardia_events) FROM most_unstable_cohort_metrics) AS avg_tachycardia_events_quartile,
  (SELECT AVG(map_low_events) FROM most_unstable_cohort_metrics) AS avg_map_low_events_quartile,
  (SELECT AVG(tachypnea_events) FROM most_unstable_cohort_metrics) AS avg_tachypnea_events_quartile,
  (SELECT AVG(los) FROM most_unstable_cohort_metrics) AS avg_los_quartile,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM most_unstable_cohort_metrics) AS mortality_quartile,
  -- All cohort metrics
  (SELECT AVG(tachycardia_events) FROM cohort_metrics) AS avg_tachycardia_events_all,
  (SELECT AVG(map_low_events) FROM cohort_metrics) AS avg_map_low_events_all,
  (SELECT AVG(tachypnea_events) FROM cohort_metrics) AS avg_tachypnea_events_all,
  (SELECT AVG(los) FROM cohort_metrics) AS avg_los_all,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM cohort_metrics) AS mortality_all
FROM UNNEST([1])

UNION ALL

SELECT
  'All ICU' AS group,
  NULL AS composite_score_99th,
  -- Most unstable quartile metrics
  (SELECT AVG(tachycardia_events) FROM most_unstable_icu_metrics) AS avg_tachycardia_events_quartile,
  (SELECT AVG(map_low_events) FROM most_unstable_icu_metrics) AS avg_map_low_events_quartile,
  (SELECT AVG(tachypnea_events) FROM most_unstable_icu_metrics) AS avg_tachypnea_events_quartile,
  (SELECT AVG(los) FROM most_unstable_icu_metrics) AS avg_los_quartile,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM most_unstable_icu_metrics) AS mortality_quartile,
  -- All ICU metrics
  (SELECT AVG(tachycardia_events) FROM all_icu_metrics) AS avg_tachycardia_events_all,
  (SELECT AVG(map_low_events) FROM all_icu_metrics) AS avg_map_low_events_all,
  (SELECT AVG(tachypnea_events) FROM all_icu_metrics) AS avg_tachypnea_events_all,
  (SELECT AVG(los) FROM all_icu_metrics) AS avg_los_all,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM all_icu_metrics) AS mortality_all
FROM UNNEST([1])
;