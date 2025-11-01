WITH first_icus AS (
  -- Get first ICU stay per patient admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
demog AS (
  -- Filter to male patients age 57–67
  SELECT
    f.*,
    p.anchor_age
  FROM
    first_icus f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),
-- Identify itemids for each instability measure
temp_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
),
spo2_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%o2 saturation%'
     OR LOWER(label) LIKE '%oxygen saturation%'
),
rr_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
events72 AS (
  -- Pull relevant chartevents in first 72h of ICU stay
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    ce.itemid,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN demog d
      ON ce.subject_id = d.subject_id
     AND ce.hadm_id    = d.hadm_id
     AND ce.stay_id    = d.stay_id
  WHERE
    ce.charttime BETWEEN d.intime
      AND TIMESTAMP_ADD(d.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      ce.itemid IN (SELECT itemid FROM temp_ids)
      OR ce.itemid IN (SELECT itemid FROM spo2_ids)
      OR ce.itemid IN (SELECT itemid FROM rr_ids)
    )
),
instability AS (
  -- Count events by type
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(CASE WHEN itemid IN (SELECT itemid FROM temp_ids) AND valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_events,
    SUM(CASE WHEN itemid IN (SELECT itemid FROM spo2_ids) AND valuenum < 90    THEN 1 ELSE 0 END) AS spo2_events,
    SUM(CASE WHEN itemid IN (SELECT itemid FROM rr_ids ) AND valuenum > 20    THEN 1 ELSE 0 END) AS rr_events
  FROM events72
  GROUP BY subject_id, hadm_id, stay_id
),
composite AS (
  -- Combine counts, join LOS and mortality flag and transplant flag
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    IFNULL(i.fever_events, 0) + IFNULL(i.spo2_events, 0) + IFNULL(i.rr_events, 0) AS composite_score,
    d.los,
    adm.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = d.subject_id
        AND di.hadm_id = d.hadm_id
        AND LOWER(dd.long_title) LIKE '%transplant%'
    ) THEN 'Transplant' ELSE 'Non-Transplant' END AS transplant_flag
  FROM
    demog d
    LEFT JOIN instability i
      ON d.subject_id = i.subject_id
     AND d.hadm_id    = i.hadm_id
     AND d.stay_id    = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON d.subject_id = adm.subject_id
     AND d.hadm_id    = adm.hadm_id
)
SELECT
  transplant_flag,
  -- Composite instability score percentiles
  APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] AS composite_p25,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] AS composite_median,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS composite_p75,
  -- ICU LOS percentiles
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_p25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_p75,
  -- Mortality rate
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_percent
FROM
  composite
GROUP BY
  transplant_flag
ORDER BY
  transplant_flag;