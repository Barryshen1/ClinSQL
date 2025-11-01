WITH base_patients AS (
  SELECT 
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
admissions_with_age AS (
  SELECT 
    bp.*,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year AS age_at_adm
  FROM base_patients bp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON bp.subject_id = a.subject_id
),
all_females AS (
  SELECT *
  FROM admissions_with_age
  WHERE age_at_adm BETWEEN 43 AND 53
),
cohort AS (
  SELECT *
  FROM all_females af
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
    WHERE i.subject_id = af.subject_id AND i.hadm_id = af.hadm_id
  )
  AND EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    WHERE di.subject_id = af.subject_id 
      AND di.hadm_id = af.hadm_id
      AND ((di.icd_version = 9 AND di.icd_code LIKE '428%') 
           OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%'))
  )
),
drg_cohort AS (
  SELECT 
    c.*,
    COALESCE(drg.drg_mortality, 1) AS risk_score
  FROM cohort c
  LEFT JOIN (
    SELECT subject_id, hadm_id, drg_mortality
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'MS'
  ) drg
    ON c.subject_id = drg.subject_id AND c.hadm_id = drg.hadm_id
),
cohort_with_metrics AS (
  SELECT 
    dc.*,
    CASE 
      WHEN hospital_expire_flag = 1 
        AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1
      WHEN hospital_expire_flag = 0 
        AND dod IS NOT NULL 
        AND DATE(dod) <= DATE(TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) THEN 1
      ELSE 0
    END AS died_30d,
    CASE WHEN hospital_expire_flag = 0 
      THEN DATETIME_DIFF(dischtime, admittime, DAY) 
      ELSE NULL 
    END AS los_days,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dig 
      WHERE dig.subject_id = dc.subject_id 
        AND dig.hadm_id = dc.hadm_id
        AND ((dig.icd_version = 9 AND dig.icd_code LIKE '584%') 
             OR (dig.icd_version = 10 AND dig.icd_code LIKE 'N17%'))
    ) AS has_major_comp
  FROM drg_cohort dc
),
cohort_stats AS (
  SELECT 
    APPROX_QUANTILES(risk_score, 4)[OFFSET(1)] AS q1_risk,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS median_risk,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS q3_risk,
    SAFE_DIVIDE(COUNTIF(died_30d = 1), COUNT(*)) AS mortality_30d_rate,
    SAFE_DIVIDE(COUNTIF(has_major_comp = TRUE), COUNT(*)) AS major_comp_rate,
    AVG(los_days) AS avg_los_survivors
  FROM cohort_with_metrics
),
all_with_risk AS (
  SELECT 
    af.*,
    COALESCE(drg.drg_mortality, 1) AS risk_score
  FROM all_females af
  LEFT JOIN (
    SELECT subject_id, hadm_id, drg_mortality
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'MS'
  ) drg
    ON af.subject_id = drg.subject_id AND af.hadm_id = drg.hadm_id
),
all_risk_dist AS (
  SELECT 
    risk_score,
    COUNT(*) AS cnt
  FROM all_with_risk
  GROUP BY risk_score
)
SELECT 
  cs.q1_risk,
  cs.median_risk,
  cs.q3_risk,
  cs.mortality_30d_rate,
  cs.major_comp_rate,
  cs.avg_los_survivors,
  SAFE_DIVIDE(
    (SELECT SUM(ard.cnt) FROM all_risk_dist ard WHERE ard.risk_score <= cs.median_risk),
    (SELECT SUM(ard.cnt) FROM all_risk_dist ard)
  ) * 100 AS risk_percentile
FROM cohort_stats cs;