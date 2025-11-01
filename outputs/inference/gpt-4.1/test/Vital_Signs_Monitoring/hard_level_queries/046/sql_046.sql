WITH ischemic_stroke_icds AS (
  -- ICD-10: I63, I65, I66; ICD-9: 433.x1, 434.x1, 436
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I63') OR
      REGEXP_CONTAINS(icd_code, r'^I65') OR
      REGEXP_CONTAINS(icd_code, r'^I66')
    ))
    OR
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^433') OR
      REGEXP_CONTAINS(icd_code, r'^434') OR
      icd_code = '436'
    ))
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN ischemic_stroke_icds stroke
    ON diag.icd_code = stroke.icd_code AND diag.icd_version = stroke.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
),
-- Step 2: Get vital sign itemids
vital_sign_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(category) IN (
    'heart rate', 'blood pressure', 'respiratory rate', 'temperature', 'oxygen saturation'
  )
  OR LOWER(label) IN (
    'heart rate', 'hr', 'systolic blood pressure', 'diastolic blood pressure',
    'mean blood pressure', 'respiratory rate', 'temperature', 'spo2', 'o2 saturation'
  )
),
-- Step 3: Get normal ranges for vital signs
vital_sign_norms AS (
  SELECT
    itemid,
    CAST(lownormalvalue AS FLOAT64) AS low,
    CAST(highnormalvalue AS FLOAT64) AS high
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE itemid IN (SELECT itemid FROM vital_sign_items)
),
-- Step 4: Calculate instability score for each ICU stay (count of abnormal vital signs in first 72h)
instability_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNTIF(
      ce.valuenum IS NOT NULL
      AND (
        (vsn.low IS NOT NULL AND ce.valuenum < vsn.low)
        OR
        (vsn.high IS NOT NULL AND ce.valuenum > vsn.high)
      )
    ) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
  JOIN vital_sign_items vsi
    ON ce.itemid = vsi.itemid
  LEFT JOIN vital_sign_norms vsn
    ON ce.itemid = vsn.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
-- Step 5: Calculate percentile of score=80
score_distribution AS (
  SELECT
    instability_score,
    COUNT(*) AS n
  FROM instability_scores
  GROUP BY instability_score
),
score_percentile AS (
  SELECT
    80 AS target_score,
    -- Percentile rank: % of scores <= 80
    100.0 * SUM(n) OVER (ORDER BY instability_score ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(n) OVER () AS percentile
  FROM score_distribution
  WHERE instability_score <= 80
  ORDER BY instability_score DESC
  LIMIT 1
),
-- Step 6: Get LOS and mortality for top instability quartile
quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q3_score
  FROM instability_scores
),
top_quartile AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.instability_score
  FROM instability_scores s
  CROSS JOIN quartile_cutoff q
  WHERE s.instability_score >= q.q3_score
),
top_quartile_outcomes AS (
  SELECT
    tq.subject_id,
    tq.hadm_id,
    tq.stay_id,
    tq.instability_score,
    icu.los,
    adm.hospital_expire_flag AS mortality
  FROM top_quartile tq
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON tq.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON tq.hadm_id = adm.hadm_id
)
-- Final output: percentile for score=80, and LOS/mortality for top quartile
SELECT
  'Percentile for instability score of 80' AS metric,
  sp.percentile
FROM score_percentile sp

UNION ALL

SELECT
  'Top quartile ICU LOS (mean, days)' AS metric,
  AVG(los)
FROM top_quartile_outcomes

UNION ALL

SELECT
  'Top quartile mortality rate (%)' AS metric,
  100.0 * AVG(CAST(mortality AS FLOAT64))
FROM top_quartile_outcomes
;