WITH eligible AS (
  -- Compute age at admission and filter to female, age 59-69
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.subject_id,
    CASE
      WHEN p.anchor_age IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND CASE
          WHEN p.anchor_age IS NOT NULL THEN
            p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
          ELSE NULL
        END BETWEEN 59 AND 69
),
pe_hadm AS (
  -- Admissions with PE (ICD-9 415% or ICD-10 I26%)
  SELECT DISTINCT e.hadm_id
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.hadm_id = e.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '415%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
),
-- Charlson-like comorbidity flags
comorb_flags AS (
  SELECT d.hadm_id,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '412%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
              THEN 1 ELSE 0 END) AS mi_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%')
                   OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
              THEN 1 ELSE 0 END) AS chf_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (
                        d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR
                        d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR
                        d.icd_code LIKE '436%' OR d.icd_code LIKE '437%' OR
                        d.icd_code LIKE '438%'))
                   OR (d.icd_version = 10 AND (
                        d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR
                        d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR
                        d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I69%'))
              THEN 1 ELSE 0 END) AS cvd_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '496%'))
                   OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
              THEN 1 ELSE 0 END) AS copd_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E10%'))
              THEN 1 ELSE 0 END) AS diabetes_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '580%' OR d.icd_code LIKE '581%' OR d.icd_code LIKE '582%' OR d.icd_code LIKE '583%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%' OR d.icd_code LIKE '589%' OR d.icd_code LIKE '584%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%'))
              THEN 1 ELSE 0 END) AS renal_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '570%' OR d.icd_code LIKE '571%' OR d.icd_code LIKE '572%' OR d.icd_code LIKE '573%' OR d.icd_code LIKE '574%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K75%' OR d.icd_code LIKE 'K76%' OR d.icd_code LIKE 'K77%'))
              THEN 1 ELSE 0 END) AS liver_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '140%' OR d.icd_code LIKE '141%' OR d.icd_code LIKE '142%' OR d.icd_code LIKE '143%' OR
                                       d.icd_code LIKE '144%' OR d.icd_code LIKE '145%' OR d.icd_code LIKE '146%' OR d.icd_code LIKE '147%' OR
                                       d.icd_code LIKE '148%' OR d.icd_code LIKE '149%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'C00%' OR d.icd_code LIKE 'C01%' OR d.icd_code LIKE 'C02%' OR
                                        d.icd_code LIKE 'C03%' OR d.icd_code LIKE 'C04%' OR d.icd_code LIKE 'C05%' OR d.icd_code LIKE 'C06%' OR d.icd_code LIKE 'C07%' OR d.icd_code LIKE 'C08%' OR d.icd_code LIKE 'C09%' OR d.icd_code LIKE 'C10%'))
              THEN 1 ELSE 0 END) AS cancer_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%'))
              THEN 1 ELSE 0 END) AS mets_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '042%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'B20%'))
              THEN 1 ELSE 0 END) AS aids_flag,
         MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '290%'))
                   OR (d.icd_version = 10 AND (d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%'))
              THEN 1 ELSE 0 END) AS dementia_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE d.hadm_id IN (SELECT hadm_id FROM pe_hadm)
  GROUP BY d.hadm_id
),
comorb_score AS (
  SELECT c.hadm_id,
         IFNULL(mi_flag, 0) + IFNULL(chf_flag, 0) + IFNULL(cvd_flag, 0) + IFNULL(copd_flag, 0)
           + IFNULL(diabetes_flag, 0) + IFNULL(renal_flag, 0) + IFNULL(liver_flag, 0)
           + IFNULL(cancer_flag, 0) + IFNULL(mets_flag, 0) + IFNULL(aids_flag, 0) + IFNULL(dementia_flag, 0) AS comorb_score
  FROM comorb_flags c
),
case_set AS (
  SELECT e.hadm_id, e.admittime, e.dischtime, e.deathtime, cs.comorb_score
  FROM eligible AS e
  JOIN comorb_score AS cs ON cs.hadm_id = e.hadm_id
  JOIN pe_hadm AS pe ON pe.hadm_id = e.hadm_id
  WHERE cs.comorb_score >= 3
),
case_case_neuro AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.comorb_score,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      WHERE di2.hadm_id = c.hadm_id
        AND (
          (di2.icd_version = 9 AND (di2.icd_code LIKE '410%' OR di2.icd_code LIKE '412%' OR di2.icd_code LIKE '427%' OR di2.icd_code LIKE '428%'))
          OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'I21%' OR di2.icd_code LIKE 'I22%' OR di2.icd_code LIKE 'I47%' OR di2.icd_code LIKE 'I48%' OR di2.icd_code LIKE 'I49%' OR di2.icd_code LIKE 'I50%' OR di2.icd_code LIKE 'I60%' OR di2.icd_code LIKE 'I63%'))
          OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'G40%'))
        )
    ) THEN 1 ELSE 0 END AS cardio_neuro_flag
  FROM case_set AS c
),
case_los AS (
  SELECT
    cls.hadm_id,
    cls.admittime,
    cls.dischtime,
    cls.deathtime,
    cls.comorb_score,
    CASE WHEN cls.deathtime IS NULL THEN TIMESTAMP_DIFF(cls.dischtime, cls.admittime, DAY) END AS survivor_los_days
  FROM case_case_neuro AS cls
),
controls_base AS (
  SELECT e.hadm_id,
         e.admittime,
         e.dischtime,
         e.deathtime,
         cs.comorb_score
  FROM eligible AS e
  JOIN comorb_score AS cs ON cs.hadm_id = e.hadm_id
  WHERE e.hadm_id NOT IN (SELECT hadm_id FROM pe_hadm)
),
controls_neuro AS (
  SELECT cb.hadm_id,
         cb.admittime,
         cb.dischtime,
         cb.deathtime,
         cb.comorb_score,
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
           WHERE di2.hadm_id = cb.hadm_id
             AND (
               (di2.icd_version = 9 AND (di2.icd_code LIKE '410%' OR di2.icd_code LIKE '412%' OR di2.icd_code LIKE '427%' OR di2.icd_code LIKE '428%'))
               OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'I21%' OR di2.icd_code LIKE 'I22%' OR di2.icd_code LIKE 'I47%' OR di2.icd_code LIKE 'I48%' OR di2.icd_code LIKE 'I49%' OR di2.icd_code LIKE 'I50%' OR di2.icd_code LIKE 'I60%' OR di2.icd_code LIKE 'I63%'))
               OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'G40%'))
             )
         ) THEN 1 ELSE 0 END AS cardio_neuro_flag
  FROM controls_base AS cb
),
controls_los AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.comorb_score,
    CASE WHEN a.deathtime IS NULL THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) END AS survivor_los_days
  FROM controls_neuro AS a
),
-- Controls as a separate, clearly named set for percentile calculations
controls_cte AS (
  SELECT cb.hadm_id,
         cb.admittime,
         cb.dischtime,
         cb.deathtime,
         cb.comorb_score
  FROM controls_base AS cb
)

-- Final aggregation: compute requested metrics
SELECT
  -- Mean comorbidity score in cases
  (SELECT AVG(comorb_score) FROM case_los) AS mean_comorbidity_case,

  -- 30-day mortality among cases
  (SELECT AVG(CASE WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30 THEN 1 ELSE 0 END)
   FROM case_los) AS mortality_30d_case,

  -- Cardio/neurologic complication rate among cases
  (SELECT AVG(cardio_neuro_flag)
   FROM (
     SELECT c.hadm_id,
            CASE WHEN EXISTS (
              SELECT 1
              FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
              WHERE di2.hadm_id = c.hadm_id
                AND (
                  (di2.icd_version = 9 AND (di2.icd_code LIKE '410%' OR di2.icd_code LIKE '412%' OR di2.icd_code LIKE '427%' OR di2.icd_code LIKE '428%'))
                  OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'I21%' OR di2.icd_code LIKE 'I22%' OR di2.icd_code LIKE 'I47%' OR di2.icd_code LIKE 'I48%' OR di2.icd_code LIKE 'I49%' OR di2.icd_code LIKE 'I50%' OR di2.icd_code LIKE 'I60%' OR di2.icd_code LIKE 'I63%'))
                  OR (di2.icd_version = 10 AND (di2.icd_code LIKE 'G40%'))
                )
            ) THEN 1 ELSE 0 END AS cardio_neuro_flag
     FROM case_set AS c
   )) AS cardio_neuro_rate_case,

  -- Survivor LOS (mean days) among cases (only survivors)
  (SELECT AVG(survivor_los_days)
   FROM case_los
   WHERE deathtime IS NULL) AS survivor_los_case,

  -- Cardio/neurologic complication rate among controls
  (SELECT AVG(CAST(cardio_neuro_flag AS INT64))
   FROM controls_neuro) AS cardio_neuro_rate_control,

  -- Survivor LOS among controls (mean days, for survivors)
  (SELECT AVG(survivor_los_days)
   FROM controls_los
   WHERE deathtime IS NULL) AS survivor_los_control,

  -- Percentile-like profile: mean percentile of case comorbidity score within controls
  (SELECT AVG(pctl)
   FROM (
     SELECT c.hadm_id,
            1.0 * (SELECT COUNT(*) FROM controls_cte WHERE comorb_score <= c.comorb_score) /
            (SELECT COUNT(*) FROM controls_cte) AS pctl
     FROM case_set AS c
   )) AS mean_profile_percentile;