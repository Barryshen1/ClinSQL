WITH base_cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime, 
    ie.outtime, 
    ie.los, 
    p.anchor_age, 
    p.gender, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code 
        AND di.icd_version = dd.icd_version
      WHERE di.subject_id = ie.subject_id 
        AND di.hadm_id = ie.hadm_id
        AND di.icd_code LIKE 'J96%'
    )
),
hfnc_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow%'
    AND LOWER(label) LIKE '%nasal cannula%'
),
has_hfnc AS (
  SELECT 
    bc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        INNER JOIN hfnc_itemids hi ON pe.itemid = hi.itemid
        WHERE pe.stay_id = bc.stay_id
          AND pe.starttime >= bc.intime
          AND pe.starttime <= TIMESTAMP_ADD(bc.intime, INTERVAL 24 HOUR)
      ) THEN 1 
      ELSE 0 
    END AS hfnc_group
  FROM base_cohort bc
),
patient_burdens AS (
  SELECT 
    hh.stay_id,
    hh.hfnc_group,
    hh.los,
    hh.hospital_expire_flag,
    COALESCE(
      SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1.0 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN ce.itemid = 220045 THEN 1.0 ELSE 0 END), 0),
      0
    ) * 100 AS tach_burden,
    COALESCE(
      SUM(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1.0 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN ce.itemid = 220179 THEN 1.0 ELSE 0 END), 0),
      0
    ) * 100 AS hypo_burden,
    -- Proxy instability score: average of tach and hypo burdens
    COALESCE(
      (SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1.0 ELSE 0 END) /
       NULLIF(SUM(CASE WHEN ce.itemid = 220045 THEN 1.0 ELSE 0 END), 0) +
       SUM(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1.0 ELSE 0 END) /
       NULLIF(SUM(CASE WHEN ce.itemid = 220179 THEN 1.0 ELSE 0 END), 0)) / 2,
      0
    ) * 100 AS instability_score
  FROM has_hfnc hh
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON hh.stay_id = ce.stay_id
    AND ce.charttime BETWEEN hh.intime AND hh.outtime
    AND ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
  GROUP BY 
    hh.stay_id, hh.hfnc_group, hh.los, hh.hospital_expire_flag
)
SELECT 
  hfnc_group,
  COUNT(*) AS n,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
  APPROX_QUANTILES(los, 20)[OFFSET(19)] AS p95_los,
  AVG(los) AS mean_los,
  SUM(hospital_expire_flag) AS num_deaths,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  -- Tachycardia burden
  APPROX_QUANTILES(tach_burden, 4)[OFFSET(1)] AS p25_tach_burden,
  APPROX_QUANTILES(tach_burden, 4)[OFFSET(2)] AS median_tach_burden,
  APPROX_QUANTILES(tach_burden, 4)[OFFSET(3)] AS p75_tach_burden,
  -- Hypotension burden
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(1)] AS p25_hypo_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(2)] AS median_hypo_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(3)] AS p75_hypo_burden,
  -- Instability score
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS p25_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS median_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS p75_instability_score,
  APPROX_QUANTILES(instability_score, 20)[OFFSET(19)] AS p95_instability_score
FROM patient_burdens
GROUP BY hfnc_group
ORDER BY hfnc_group;