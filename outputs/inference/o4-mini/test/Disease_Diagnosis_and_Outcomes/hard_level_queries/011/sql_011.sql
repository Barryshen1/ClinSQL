WITH
-- 1. Identify AMI admissions for women aged 88-98 with ICU stays
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.dischtime,
    MIN(i.intime) OVER (PARTITION BY a.subject_id, a.hadm_id) AS first_icu_intime,
    MAX(i.outtime) OVER (PARTITION BY a.subject_id, a.hadm_id) AS last_icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id
     AND a.hadm_id    = i.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND dd.icd_version = 10
    AND dd.icd_code LIKE 'I21%'    -- AMI ICD-10
),
-- 2. Flag 30-day mortality
mort30 AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL
       AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30
      THEN 1 ELSE 0 END AS mort30_flag
  FROM cohort
),
-- 3. Flag ARDS (ICD J80)
ards AS (
  SELECT
    DISTINCT d.subject_id,
    d.hadm_id,
    1 AS ards_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_version = 10
    AND dd.icd_code = 'J80'
),
-- 4. Flag AKI via creatinine rise ≥ 0.3 mg/dL within 48h
creat AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS cr,
    LEAD(le.valuenum) OVER (
      PARTITION BY le.subject_id, le.hadm_id
      ORDER BY le.charttime
    ) AS next_cr,
    LEAD(le.charttime) OVER (
      PARTITION BY le.subject_id, le.hadm_id
      ORDER BY le.charttime
    ) AS next_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    li.category = 'Chemistry'
    AND LOWER(li.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
),
aki_flags AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(
      CASE
        WHEN next_time IS NOT NULL
         AND TIMESTAMP_DIFF(next_time, charttime, HOUR) <= 48
         AND next_cr - cr >= 0.3
        THEN 1 ELSE 0
      END
    ) AS aki_flag
  FROM creat
  GROUP BY subject_id, hadm_id
),
-- 5. Survival days for decedents post-ICU
survival AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    TIMESTAMP_DIFF(c.deathtime, c.last_icu_outtime, DAY) AS survival_days
  FROM cohort c
  WHERE c.deathtime IS NOT NULL
),
-- 6. Assemble final metrics
final AS (
  SELECT
    COUNT(*)                                AS n_patients,
    AVG(m.mort30_flag)                      AS rate_30day_mortality,
    AVG(IFNULL(a.ards_flag, 0))             AS rate_ards,
    AVG(IFNULL(k.aki_flag, 0))              AS rate_aki,
    APPROX_QUANTILES(s.survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM cohort c
  LEFT JOIN mort30 m
    ON c.subject_id = m.subject_id
   AND c.hadm_id    = m.hadm_id
  LEFT JOIN ards a
    ON c.subject_id = a.subject_id
   AND c.hadm_id    = a.hadm_id
  LEFT JOIN aki_flags k
    ON c.subject_id = k.subject_id
   AND c.hadm_id    = k.hadm_id
  LEFT JOIN survival s
    ON c.subject_id = s.subject_id
   AND c.hadm_id    = s.hadm_id
)
SELECT * FROM final;