WITH cohort AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    adm.admittime,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_hosp.patients` pt
    ON ie.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 83 AND 93
),
asthma_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '493%') OR
    (icd_version = 10 AND icd_code LIKE 'J45%')
),
combined_cohort AS (
  SELECT 
    c.*,
    CASE WHEN ad.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_asthma
  FROM cohort c
  LEFT JOIN asthma_diagnoses ad
    ON c.hadm_id = ad.hadm_id
),
ventilation AS (
  SELECT 
    stay_id,
    MAX(
      CASE WHEN itemid IN (223848, 223849) THEN 1 
      ELSE 0 END
    ) AS vent
  FROM `physionet-data.mimiciv_icu.chartevents`
  WHERE itemid IN (223848, 223849)
  GROUP BY stay_id
),
gcs AS (
  SELECT 
    stay_id AS stay_id,
    MIN(valuenum) AS gcs_min
  FROM `physionet-data.mimiciv_icu.chartevents`
  WHERE itemid IN (220739, 223900, 223901)
  GROUP BY stay_id
),
vaso AS (
  SELECT 
    ie.stay_id,
    MAX(
      CASE WHEN itemid IN (221906, 221289, 221662, 221653) THEN 1 
      ELSE 0 END
    ) AS vaso_used
  FROM `physionet-data.mimiciv_icu.inputevents` ie
  WHERE ie.itemid IN (221906, 221289, 221662, 221653)
  GROUP BY ie.stay_id
),
labs AS (
  SELECT 
    cc.stay_id,  -- Group by stay_id instead of hadm_id
    MAX(
      CASE WHEN itemid = 51265 THEN valuenum END
    ) AS platelets,
    MAX(
      CASE WHEN itemid = 50885 THEN valuenum END
    ) AS bilirubin
  FROM `physionet-data.mimiciv_hosp.labevents` le
  INNER JOIN combined_cohort cc ON le.hadm_id = cc.hadm_id
  WHERE le.itemid IN (51265, 50885)
    AND le.charttime BETWEEN cc.intime AND DATETIME_ADD(cc.intime, INTERVAL 72 HOUR)
  GROUP BY cc.stay_id  -- Ensure labs are per ICU stay
),
sofa_scores AS (
  SELECT 
    cc.stay_id,
    -- Respiration (PaO2/FiO2 or mechanical ventilation)
    CASE
      WHEN v.vent = 1 THEN 4
      WHEN MAX(CASE WHEN ce.itemid = 50821 THEN ce.valuenum END) < 100 THEN 4
      WHEN MAX(CASE WHEN ce.itemid = 50821 THEN ce.valuenum END) < 200 THEN 3
      WHEN MAX(CASE WHEN ce.itemid = 50821 THEN ce.valuenum END) < 300 THEN 2
      ELSE 0
    END AS respiration,
    -- Coagulation (platelets)
    CASE
      WHEN l.platelets < 20 THEN 4
      WHEN l.platelets < 50 THEN 3
      WHEN l.platelets < 100 THEN 2
      WHEN l.platelets < 150 THEN 1
      ELSE 0
    END AS coagulation,
    -- Liver (bilirubin)
    CASE
      WHEN l.bilirubin >= 12.0 THEN 4
      WHEN l.bilirubin >= 6.0 THEN 3
      WHEN l.bilirubin >= 2.0 THEN 2
      WHEN l.bilirubin >= 1.2 THEN 1
      ELSE 0
    END AS liver,
    -- Cardiovascular (vasopressors)
    COALESCE(vs.vaso_used * 2, 0) AS cardiovascular,  -- Simplified: any vasopressor use = 2 points
    -- CNS (GCS)
    CASE
      WHEN g.gcs_min < 6 THEN 4
      WHEN g.gcs_min < 10 THEN 3
      WHEN g.gcs_min < 13 THEN 2
      WHEN g.gcs_min < 15 THEN 1
      ELSE 0
    END AS cns,
    -- Renal (creatinine/urine output omitted for brevity, default 0)
    0 AS renal
  FROM combined_cohort cc
  LEFT JOIN ventilation v ON cc.stay_id = v.stay_id
  LEFT JOIN gcs g ON cc.stay_id = g.stay_id
  LEFT JOIN vaso vs ON cc.stay_id = vs.stay_id
  LEFT JOIN labs l ON cc.stay_id = l.stay_id  -- Join on stay_id instead of hadm_id
  LEFT JOIN `physionet-data.mimiciv_icu.chartevents` ce 
    ON cc.stay_id = ce.stay_id AND  -- Added missing keyword ON
    ce.itemid = 50821 AND  -- PaO2
    ce.charttime BETWEEN cc.intime AND DATETIME_ADD(cc.intime, INTERVAL 72 HOUR)
  GROUP BY cc.stay_id, v.vent, l.platelets, l.bilirubin, vs.vaso_used, g.gcs_min
)
SELECT 
  cc.has_asthma AS cohort,
  COUNT(*) AS num_patients,
  AVG(respiration + coagulation + liver + cardiovascular + cns + renal) AS avg_sofa,
  STDDEV(respiration + coagulation + liver + cardiovascular + cns + renal) AS sd_sofa,
  APPROX_QUANTILES(respiration + coagulation + liver + cardiovascular + cns + renal, 100)[OFFSET(25)] AS p25_sofa,
  APPROX_QUANTILES(respiration + coagulation + liver + cardiovascular + cns + renal, 100)[OFFSET(50)] AS p50_sofa,
  APPROX_QUANTILES(respiration + coagulation + liver + cardiovascular + cns + renal, 100)[OFFSET(75)] AS p75_sofa,
  APPROX_QUANTILES(respiration + coagulation + liver + cardiovascular + cns + renal, 100)[OFFSET(95)] AS p95_sofa,
  AVG(cc.los) AS avg_icu_los,
  SUM(cc.hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM combined_cohort cc
INNER JOIN sofa_scores ss ON cc.stay_id = ss.stay_id
GROUP BY cc.has_asthma;