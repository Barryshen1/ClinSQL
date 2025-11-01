WITH female_icu_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),

heart_failure_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-10: I50*, ICD-9: 428*
    (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
    OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
),

major_complications AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- Example major complication codes (expand as needed):
    -- Acute renal failure: ICD-9 584*, ICD-10 N17*
    -- Sepsis: ICD-9 99591, 99592, ICD-10 A41*
    -- Stroke: ICD-9 434*, ICD-10 I63*
    (
      (d.icd_version = 9 AND (LEFT(d.icd_code, 3) = '584' OR d.icd_code IN ('99591', '99592') OR LEFT(d.icd_code, 3) = '434'))
      OR
      (d.icd_version = 10 AND (LEFT(d.icd_code, 3) = 'N17' OR LEFT(d.icd_code, 3) = 'A41' OR LEFT(d.icd_code, 3) = 'I63'))
    )
),

icu_stays_with_risk AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    icu.stay_id,
    f.anchor_age,
    f.gender,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los,
    -- Get first SAPS II value during ICU stay (itemid=220615 is a placeholder)
    (
      SELECT ce.valuenum
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = f.subject_id
        AND ce.hadm_id = f.hadm_id
        AND ce.stay_id = icu.stay_id
        AND ce.itemid = 220615
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN icu.intime AND icu.outtime
      ORDER BY ce.charttime
      LIMIT 1
    ) AS risk_score
  FROM
    female_icu_patients f
    JOIN heart_failure_admissions hf
      ON f.subject_id = hf.subject_id AND f.hadm_id = hf.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON f.hadm_id = icu.hadm_id
),

cohort AS (
  SELECT
    s.*,
    CASE
      WHEN s.deathtime IS NOT NULL AND DATETIME_DIFF(s.deathtime, s.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    CASE
      WHEN mc.hadm_id IS NOT NULL THEN 1 ELSE 0
    END AS major_complication
  FROM
    icu_stays_with_risk s
    LEFT JOIN major_complications mc
      ON s.subject_id = mc.subject_id AND s.hadm_id = mc.hadm_id
  WHERE
    s.risk_score IS NOT NULL
),

-- For percentile calculation: all females 43-53 with ICU stays and risk score
all_female_icu_risk AS (
  SELECT
    s.risk_score
  FROM
    icu_stays_with_risk s
  WHERE
    s.risk_score IS NOT NULL
),

cohort_median AS (
  SELECT
    APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS median_risk_score
  FROM
    cohort
),

cohort_median_percentile AS (
  SELECT
    ROUND(
      100 * COUNTIF(risk_score < cm.median_risk_score) / COUNT(*), 1
    ) AS cohort_median_risk_percentile
  FROM
    all_female_icu_risk afr
    CROSS JOIN cohort_median cm
)

SELECT
  agg.n_cohort,
  agg.median_risk_score,
  agg.risk_score_iqr,
  agg.mortality_30d_rate,
  agg.major_complication_rate,
  agg.avg_los_survivors,
  cmp.cohort_median_risk_percentile
FROM (
  SELECT
    COUNT(*) AS n_cohort,
    APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS median_risk_score,
    STRUCT(
      APPROX_QUANTILES(risk_score, 4)[OFFSET(1)] AS q1,
      APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS q3
    ) AS risk_score_iqr,
    ROUND(SUM(died_30d) / COUNT(*), 3) AS mortality_30d_rate,
    ROUND(SUM(major_complication) / COUNT(*), 3) AS major_complication_rate,
    ROUND(AVG(CASE WHEN died_30d = 0 THEN los ELSE NULL END), 2) AS avg_los_survivors
  FROM
    cohort
) agg
CROSS JOIN cohort_median_percentile cmp
;