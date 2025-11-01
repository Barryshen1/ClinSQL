WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.dod,
    aps.apsiii AS risk_score,
    CASE
      WHEN p.dod IS NOT NULL AND p.dod <= DATETIME_ADD(i.intime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS mortality_30day,
    CASE
      WHEN p.dod IS NULL OR p.dod > DATETIME_ADD(i.intime, INTERVAL 30 DAY) THEN i.los
      ELSE NULL
    END AS los_survivors
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_derived.apsiii aps
    ON i.stay_id = aps.stay_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),

cohort_stats AS (
  SELECT
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS q1_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS q3_risk_score,
    AVG(los_survivors) AS avg_los_survivors,
    AVG(mortality_30day) AS mortality_30day_rate
  FROM cohort
),

all_female_43_53 AS (
  SELECT
    aps.apsiii AS risk_score
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_derived.apsiii aps
    ON i.stay_id = aps.stay_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
),

percentile_rank AS (
  SELECT
    (SELECT median_risk_score FROM cohort_stats) AS median_risk_score_cohort,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score_all,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(
      CAST(100 * (
        SELECT COUNT(*) FROM all_female_43_53
        WHERE risk_score <= (SELECT median_risk_score FROM cohort_stats)
      ) / (SELECT COUNT(*) FROM all_female_43_53) AS INT64)
    )] AS percentile_rank
  FROM all_female_43_53
)

SELECT
  c.median_risk_score,
  c.q1_risk_score,
  c.q3_risk_score,
  c.mortality_30day_rate,
  0.0 AS major_complication_rate, -- Placeholder
  c.avg_los_survivors,
  p.percentile_rank
FROM
  cohort_stats c
CROSS JOIN
  percentile_rank p;