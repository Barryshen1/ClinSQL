WITH icu_stays_filtered AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = icu.hadm_id
          AND d.icd_version = 10
          AND (d.icd_code LIKE 'Z940%' OR d.icd_code LIKE 'Z941%' 
               OR d.icd_code LIKE 'Z942%' OR d.icd_code LIKE 'Z943%' 
               OR d.icd_code LIKE 'Z944%' OR d.icd_code LIKE 'Z948%')
      ) THEN 1
      ELSE 0
    END AS is_transplant
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 57 AND 67
),

instability AS (
  SELECT 
    icu.stay_id,
    SUM(CASE WHEN ce.itemid = 223762 AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_count,
    SUM(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_count,
    SUM(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_count,
    (SUM(CASE WHEN ce.itemid = 223762 AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END)) AS instability_score
  FROM icu_stays_filtered icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (223762, 220277, 220210)
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
),

outcomes AS (
  SELECT 
    icu.stay_id,
    DATETIME_DIFF(icu.outtime, icu.intime, SECOND) / (24*60*60) AS icu_los_days,
    adm.hospital_expire_flag AS mortality
  FROM icu_stays_filtered icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),

combined AS (
  SELECT 
    icu.stay_id,
    icu.is_transplant,
    COALESCE(inst.instability_score, 0) AS instability_score,
    out.icu_los_days,
    out.mortality
  FROM icu_stays_filtered icu
  LEFT JOIN instability inst ON icu.stay_id = inst.stay_id
  LEFT JOIN outcomes out ON icu.stay_id = out.stay_id
)

SELECT
  is_transplant,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(250)] AS instability_25,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(500)] AS instability_median,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(750)] AS instability_75,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(250)] AS icu_los_25,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(500)] AS icu_los_median,
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(750)] AS icu_los_75,
  AVG(mortality) AS mortality_rate
FROM combined
GROUP BY is_transplant;