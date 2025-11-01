WITH pe_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    CAST(a.admittime AS TIMESTAMP) AS admittime,
    -- ensure both arguments are TIMESTAMP to avoid COALESCE type-mismatch
    COALESCE(CAST(a.deathtime AS TIMESTAMP), CAST(p.dod AS TIMESTAMP)) AS death_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    -- PE identification: ICD-9 ~ 415.1* , ICD-10 ~ I26*
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '4151%' OR d.icd_code LIKE '415.1%'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
    )
),

-- For each admission in the PE cohort compute:
--  - comorbidity count (distinct non-PE icd_codes)
--  - flags for cardiac and neurologic complications (based on pragmatic ICD code prefixes)
--  - death within 30 days flag and survival days (if death recorded)
admission_metrics AS (
  SELECT
    p.hadm_id,
    p.subject_id,
    p.anchor_age AS age,
    p.admittime,
    p.death_time,
    -- distinct non-PE diagnosis codes count as a proxy comorbidity burden
    COUNT(DISTINCT CASE
      WHEN NOT (
        (d.icd_version = 9 AND (d.icd_code LIKE '4151%' OR d.icd_code LIKE '415.1%'))
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
      ) THEN d.icd_code
      ELSE NULL
    END) AS comorb_count,
    -- cardiac complication flags (pragmatic ICD prefixes)
    MAX(CASE
      WHEN (d.icd_version = 9 AND (
              d.icd_code LIKE '410%'  -- acute MI
              OR d.icd_code LIKE '427%' -- arrhythmias (includes cardiac arrest 427.5)
              OR d.icd_code LIKE '428%' -- heart failure
            ))
           OR (d.icd_version = 10 AND (
              d.icd_code LIKE 'I21%' -- MI
              OR d.icd_code LIKE 'I46%' -- cardiac arrest
              OR d.icd_code LIKE 'I50%' -- heart failure
              OR d.icd_code LIKE 'I49%' -- other arrhythmias
            ))
      THEN 1 ELSE 0 END) AS cardiac_flag,
    -- neurologic complication flags (pragmatic ICD prefixes for cerebrovascular disease, seizures)
    MAX(CASE
      WHEN (d.icd_version = 9 AND (
              d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'
              OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%'
              OR d.icd_code LIKE '436%' OR d.icd_code LIKE '345%'  -- epilepsy/seizure
            ))
           OR (d.icd_version = 10 AND (
              -- I60-I69 covers cerebrovascular diseases; G40 for epilepsy
              d.icd_code LIKE 'I6%' OR d.icd_code LIKE 'G40%'
            ))
      THEN 1 ELSE 0 END) AS neuro_flag,
    -- 30-day mortality
    CASE
      WHEN p.death_time IS NOT NULL
           AND TIMESTAMP_DIFF(p.death_time, p.admittime, DAY) <= 30
      THEN 1 ELSE 0 END AS died_within_30d,
    -- survival days (null if no recorded death_time)
    CASE
      WHEN p.death_time IS NOT NULL THEN
        TIMESTAMP_DIFF(p.death_time, p.admittime, DAY)
      ELSE NULL END AS survival_days
  FROM
    pe_admissions p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.hadm_id = d.hadm_id
  GROUP BY
    p.hadm_id, p.subject_id, p.anchor_age, p.admittime, p.death_time
),

-- Compute cohort-level statistics (means, stddevs, and 75th percentile of comorbidity count)
cohort_stats AS (
  SELECT
    COUNT(*) AS n_cohort,
    AVG(age) AS mean_age,
    STDDEV_POP(age) AS std_age,
    AVG(comorb_count) AS mean_comorb,
    STDDEV_POP(comorb_count) AS std_comorb,
    (ARRAY_AGG(x ORDER BY x LIMIT 101))[OFFSET(75)] AS q75_comorb,
    SUM(died_within_30d) AS deaths_30d,
    SUM(cardiac_flag) AS cardiac_events,
    SUM(neuro_flag) AS neuro_events,
    SUM(CASE WHEN survival_days IS NOT NULL THEN 1 ELSE 0 END) AS n_decedents
  FROM (
    SELECT
      am.*,
      am.comorb_count AS x
    FROM admission_metrics am
  ) t
),

-- Because BigQuery's approx_quantiles works on arrays, compute q75 and median survival explicitly:
quantiles AS (
  SELECT
    APPROX_QUANTILES(comorb_count, 100) AS comorb_qs,
    APPROX_QUANTILES(IFNULL(survival_days, -1), 100) AS survival_qs -- map nulls to -1 so they are at low end, we will ignore -1
  FROM admission_metrics
),

-- Final aggregated cohort metrics and per-admission composite score
computed AS (
  SELECT
    am.*,
    cs.mean_age,
    cs.std_age,
    cs.mean_comorb,
    cs.std_comorb,
    q.comorb_qs[OFFSET(75)] AS comorb_q75,
    -- compute composite score as sum of z-scores; guard against std = 0
    (
      CASE WHEN cs.std_age > 0 THEN (am.age - cs.mean_age) / cs.std_age ELSE 0 END
      +
      CASE WHEN cs.std_comorb > 0 THEN (am.comorb_count - cs.mean_comorb) / cs.std_comorb ELSE 0 END
    ) AS composite_score,
    am.died_within_30d,
    am.cardiac_flag,
    am.neuro_flag,
    am.survival_days
  FROM
    admission_metrics am
  CROSS JOIN
    (SELECT
       AVG(age) AS mean_age,
       STDDEV_POP(age) AS std_age,
       AVG(comorb_count) AS mean_comorb,
       STDDEV_POP(comorb_count) AS std_comorb
     FROM admission_metrics) cs
  CROSS JOIN
    (SELECT APPROX_QUANTILES(comorb_count, 100) AS comorb_qs FROM admission_metrics) q
),

-- Determine hypothetical patient's composite score (age 84, comorb_count = top-quartile cutoff)
patient_hypothetical AS (
  SELECT
    84 AS age,
    q.comorb_qs[OFFSET(75)] AS comorb_q75,
    stats.mean_age,
    stats.std_age,
    stats.mean_comorb,
    stats.std_comorb,
    CASE WHEN stats.std_age > 0 THEN (84 - stats.mean_age) / stats.std_age ELSE 0 END
    +
    CASE WHEN stats.std_comorb > 0 THEN (q.comorb_qs[OFFSET(75)] - stats.mean_comorb) / stats.std_comorb ELSE 0 END
    AS patient_composite_score
  FROM
    (SELECT
       AVG(age) AS mean_age,
       STDDEV_POP(age) AS std_age,
       AVG(comorb_count) AS mean_comorb,
       STDDEV_POP(comorb_count) AS std_comorb
     FROM admission_metrics) stats,
    (SELECT APPROX_QUANTILES(comorb_count, 100) AS comorb_qs FROM admission_metrics) q
)

-- Final output: compute percentile of the hypothetical patient, cohort outcome rates, median survival days
SELECT
  ph.age AS hypothetical_age,
  ph.comorb_q75 AS hypothetical_comorbidity_count_75th_pct_cutoff,
  ROUND(ph.patient_composite_score, 4) AS hypothetical_composite_score,
  -- percentile of cohort with composite_score <= patient's score (0-100)
  ROUND(100.0 * SUM(CASE WHEN c.composite_score <= ph.patient_composite_score THEN 1 ELSE 0 END) / COUNT(*), 2) AS composite_score_percentile,
  -- cohort counts & rates
  COUNT(*) AS cohort_size,
  -- 30-day mortality rate (%)
  ROUND(100.0 * SUM(c.died_within_30d) / COUNT(*), 2) AS pct_30day_mortality,
  -- cardiac and neurologic complication rates (%)
  ROUND(100.0 * SUM(c.cardiac_flag) / COUNT(*), 2) AS pct_cardiac_complication,
  ROUND(100.0 * SUM(c.neuro_flag) / COUNT(*), 2) AS pct_neurologic_complication,
  -- median survival days among those with recorded death_time (exclude nulls)
  (SELECT IFNULL( NULLIF(ROUND(surv_qs[OFFSET(50)],0), -1), NULL)
   FROM (SELECT APPROX_QUANTILES(IFNULL(survival_days, -1), 100) AS surv_qs FROM admission_metrics)
  ) AS median_survival_days_among_decedents
FROM
  computed c
CROSS JOIN
  patient_hypothetical ph;