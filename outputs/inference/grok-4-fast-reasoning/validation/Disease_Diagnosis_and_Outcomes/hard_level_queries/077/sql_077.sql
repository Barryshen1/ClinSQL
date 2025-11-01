WITH admissions_with_pneumonia AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    deathtime, 
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM (
    SELECT DISTINCT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime, 
      a.deathtime, 
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 88 AND 98
      AND d.seq_num = 1
      AND (
        (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^48[0-6]'))
        OR (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
      )
  ) sub
),
cohort AS (
  SELECT 
    ap.*,
    i.stay_id, 
    i.intime
  FROM admissions_with_pneumonia ap
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON ap.subject_id = i.subject_id AND ap.hadm_id = i.hadm_id
  WHERE ap.rn = 1
),
first_cohort AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime ASC) AS rn_stay
  FROM cohort
),
annotated_cohort AS (
  SELECT 
    fc.*,
    1 AS age_point,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
        WHERE l.hadm_id = fc.hadm_id
          AND l.itemid = 810
          AND l.valuenum IS NOT NULL
          AND l.valuenum > 19
          AND l.charttime >= fc.intime
          AND l.charttime <= TIMESTAMP_ADD(fc.intime, INTERVAL 1 DAY)
      ) THEN 1 
      ELSE 0 
    END AS urea_point,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
        WHERE ch.stay_id = fc.stay_id
          AND ch.itemid = 618
          AND ch.valuenum IS NOT NULL
          AND ch.valuenum >= 30
          AND ch.charttime >= fc.intime
          AND ch.charttime <= TIMESTAMP_ADD(fc.intime, INTERVAL 1 DAY)
      ) THEN 1 
      ELSE 0 
    END AS rr_point,
    CASE 
      WHEN ( (
        SELECT MIN(ch.valuenum) 
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
        WHERE ch.stay_id = fc.stay_id
          AND ch.itemid IN (51, 220179)
          AND ch.valuenum IS NOT NULL
          AND ch.charttime >= fc.intime
          AND ch.charttime <= TIMESTAMP_ADD(fc.intime, INTERVAL 1 DAY)
      ) < 90
      OR (
        SELECT MIN(ch.valuenum) 
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
        WHERE ch.stay_id = fc.stay_id
          AND ch.itemid IN (836, 220180)
          AND ch.valuenum IS NOT NULL
          AND ch.charttime >= fc.intime
          AND ch.charttime <= TIMESTAMP_ADD(fc.intime, INTERVAL 1 DAY)
      ) <= 60 ) THEN 1 
      ELSE 0 
    END AS bp_point,
    CASE 
      WHEN (
        SELECT MIN(ch.valuenum) 
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
        WHERE ch.stay_id = fc.stay_id
          AND ch.itemid = 220045
          AND ch.valuenum IS NOT NULL
          AND ch.charttime >= fc.intime
          AND ch.charttime <= TIMESTAMP_ADD(fc.intime, INTERVAL 1 DAY)
      ) < 15 THEN 1 
      ELSE 0 
    END AS confusion_point,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = fc.hadm_id
          AND (
            (di.icd_version = '9' AND di.icd_code LIKE '584%')
            OR (di.icd_version = '10' AND di.icd_code LIKE 'N17%')
          )
      ) THEN 1 
      ELSE 0 
    END AS has_aki,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = fc.hadm_id
          AND (
            (di.icd_version = '9' AND di.icd_code IN ('5185', '51851', '51852'))
            OR (di.icd_version = '10' AND di.icd_code = 'J80')
          )
      ) THEN 1 
      ELSE 0 
    END AS has_ards,
    CASE 
      WHEN fc.deathtime IS NOT NULL THEN 
        TIMESTAMP_DIFF(fc.deathtime, fc.admittime, HOUR) / 24.0
      ELSE NULL 
    END AS survival_days
  FROM first_cohort fc
  WHERE fc.rn_stay = 1
),
risk_cohort AS (
  SELECT 
    *,
    age_point + urea_point + rr_point + bp_point + confusion_point AS risk_score
  FROM annotated_cohort
)
SELECT 
  COUNT(*) AS cohort_size,
  MIN(risk_score) AS min_risk_score,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(1)] AS p25_risk_score,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS median_risk_score,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS p75_risk_score,
  MAX(risk_score) AS max_risk_score,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100, 2) AS in_hospital_mortality_rate,
  ROUND(SAFE_DIVIDE(SUM(has_aki), COUNT(*)) * 100, 2) AS aki_rate,
  ROUND(SAFE_DIVIDE(SUM(has_ards), COUNT(*)) * 100, 2) AS ards_rate,
  ROUND(PERCENTILE_CONT(survival_days, 0.5) IGNORE NULLS, 2) AS median_survival_days_decedents
FROM risk_cohort;